//// A process for loading zones into memory and then spinning them up
//// into processes.
//// 

import gleam/bool
import gleam/dict
import gleam/erlang/process
import gleam/list
import gleam/option.{None, Some}
import gleam/order
import gleam/otp/actor
import gleam/otp/static_supervisor
import gleam/otp/supervision.{worker}
import gleam/result
import gleam/string
import lore/world
import lore/world/items
import lore/world/mapper
import lore/world/room
import lore/world/sql
import lore/world/system_tables
import lore/world/zone
import pog

pub fn supervisor(
  system_tables: system_tables.Lookup,
) -> Result(actor.Started(static_supervisor.Supervisor), actor.StartError) {
  use zones <- result.try(
    load_zones(system_tables.db)
    |> result.map_error(fn(error) { actor.InitFailed(string.inspect(error)) }),
  )

  static_supervisor.new(static_supervisor.OneForOne)
  |> static_supervisor.add(
    worker(fn() { items.start(system_tables.items, system_tables.db) }),
  )
  // Each zone gets a supervisor
  |> list.fold(zones, _, fn(acc, zone) {
    static_supervisor.add(acc, zone_supervised(zone, system_tables))
  })
  |> static_supervisor.add(
    worker(fn() { mapper.start(system_tables.mapper, system_tables.db) }),
  )
  |> static_supervisor.start
}

fn zone_supervised(
  zone: world.Zone,
  system_tables: system_tables.Lookup,
) -> supervision.ChildSpecification(static_supervisor.Supervisor) {
  static_supervisor.new(static_supervisor.OneForOne)
  |> static_supervisor.add(worker(fn() { zone.start(zone, system_tables) }))
  |> list.fold(zone.rooms, _, fn(acc, room) {
    static_supervisor.add(acc, worker(fn() { room.start(room, system_tables) }))
  })
  |> static_supervisor.supervised
}

fn load_zones(
  db: process.Name(pog.Message),
) -> Result(List(world.Zone), pog.QueryError) {
  let db = pog.named_connection(db)
  use pog.Returned(rows: zones, ..) <- result.try(sql.zones(db))
  use pog.Returned(rows: rooms, ..) <- result.try(sql.rooms(db))
  use pog.Returned(rows: doors, ..) <- result.try(sql.doors(db))
  use pog.Returned(rows: exits, ..) <- result.try(sql.exits(db))

  let doors =
    list.map(doors, fn(door) {
      let id = door.door_id
      let state = case door.access_state {
        sql.Open -> world.Open
        sql.Closed -> world.Closed
      }
      #(id, world.Door(id: world.Id(id), state:))
    })
    |> dict.from_list

  let exits =
    list.map(exits, fn(exit) {
      let id = exit.exit_id
      let door =
        option.then(exit.door_id, fn(id) {
          case dict.get(doors, id) {
            Ok(door) -> Some(door)
            Error(Nil) -> None
          }
        })

      world.RoomExit(
        id: world.Id(id),
        keyword: string_to_direction(exit.keyword),
        from_room_id: world.Id(exit.from_room_id),
        to_room_id: world.Id(exit.to_room_id),
        door:,
      )
    })
    |> list.group(fn(exit) { exit.from_room_id })

  let rooms =
    list.map(rooms, fn(room) {
      let sql.RoomsRow(symbol:, x:, y:, z:, name:, description:, ..) = room
      let id = world.Id(room.room_id)
      let exits =
        dict.get(exits, id)
        |> result.unwrap([])
        |> list.sort(fn(a, b) { direction_order(a.keyword, b.keyword) })

      world.Room(
        id:,
        zone_id: world.Id(room.zone_id),
        symbol:,
        x:,
        y:,
        z:,
        name:,
        description:,
        items: [],
        characters: [],
        exits:,
      )
    })

  list.map(zones, fn(zone) {
    world.Zone(id: world.Id(zone.zone_id), name: zone.name, rooms:)
  })
  |> Ok
}

fn string_to_direction(exit_keyword: String) -> world.Direction {
  case exit_keyword {
    "north" -> world.North
    "south" -> world.South
    "east" -> world.East
    "west" -> world.West
    "up" -> world.Up
    "down" -> world.Down
    custom -> world.CustomExit(custom)
  }
}

fn direction_order(a: world.Direction, b: world.Direction) -> order.Order {
  use <- bool.guard(a == b, order.Eq)
  use <- bool.guard(a == world.North, order.Gt)
  case direction_to_int(a) > direction_to_int(b) {
    True -> order.Gt
    False -> order.Lt
  }
}

fn direction_to_int(direction: world.Direction) -> Int {
  case direction {
    world.North -> 1
    world.South -> 2
    world.East -> 3
    world.West -> 4
    world.Up -> 5
    world.Down -> 6
    world.CustomExit(_) -> 7
  }
}
