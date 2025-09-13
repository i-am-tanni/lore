//// A process for loading zones into memory and then spinning them up
//// into processes.
//// 

import gleam/dict
import gleam/erlang/process
import gleam/list
import gleam/option.{None, Some}
import gleam/otp/actor
import gleam/otp/static_supervisor
import gleam/otp/supervision.{worker}
import gleam/result
import lore/world
import lore/world/items
import lore/world/mapper
import lore/world/room
import lore/world/sql
import lore/world/system_tables
import lore/world/zone
import pog

pub fn supervised(
  system_tables: system_tables.Lookup,
) -> Result(actor.Started(static_supervisor.Supervisor), actor.StartError) {
  let supervisor = static_supervisor.new(static_supervisor.OneForOne)
  // Each zone gets a supervisor
  use zones <- result.try(
    load_zones(system_tables.db)
    |> result.replace_error(actor.InitFailed("Unable to load zones from db.")),
  )

  zones
  |> list.fold(supervisor, fn(acc, zone) {
    static_supervisor.add(acc, zone_supervised(zone, system_tables))
  })
  |> static_supervisor.add(
    worker(fn() { mapper.start(system_tables.mapper, zones) }),
  )
  |> static_supervisor.add(
    worker(fn() { items.start(system_tables.items, system_tables.db) }),
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
        keyword: world.string_to_direction(exit.keyword),
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
      let exits = dict.get(exits, id) |> result.unwrap([])
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
