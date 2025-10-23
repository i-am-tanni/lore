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
import lore/world.{Id}
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
  |> list.fold(zone.rooms, _, fn(acc, room) {
    static_supervisor.add(acc, worker(fn() { room.start(room, system_tables) }))
  })
  |> static_supervisor.add(worker(fn() { zone.start(zone, system_tables) }))
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
  use pog.Returned(rows: mob_spawns, ..) <- result.try(sql.mob_spawns(db))
  use pog.Returned(rows: item_spawns, ..) <- result.try(sql.item_spawns(db))
  use pog.Returned(rows: spawn_groups, ..) <- result.try(sql.spawn_groups(db))

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

  let mob_spawns =
    list.fold(mob_spawns, dict.new(), fn(acc, spawn) {
      let sql.MobSpawnsRow(mob_spawn_id:, spawn_group_id:, mobile_id:, room_id:) =
        spawn

      let mob_spawn =
        world.MobSpawn(
          spawn_id: Id(mob_spawn_id),
          mobile_id: Id(mobile_id),
          room_id: Id(room_id),
        )
      case dict.get(acc, spawn_group_id) {
        Ok(list) -> dict.insert(acc, spawn_group_id, [mob_spawn, ..list])
        Error(Nil) -> dict.insert(acc, spawn_group_id, [mob_spawn])
      }
    })

  let item_spawns =
    list.fold(item_spawns, dict.new(), fn(acc, spawn) {
      let sql.ItemSpawnsRow(item_spawn_id:, spawn_group_id:, item_id:, room_id:) =
        spawn

      let item_spawn =
        world.ItemSpawn(
          spawn_id: Id(item_spawn_id),
          item_id: Id(item_id),
          room_id: Id(room_id),
        )
      case dict.get(acc, spawn_group_id) {
        Ok(list) -> dict.insert(acc, spawn_group_id, [item_spawn, ..list])
        Error(Nil) -> dict.insert(acc, spawn_group_id, [item_spawn])
      }
    })

  let spawn_groups =
    list.map(spawn_groups, fn(group) {
      let sql.SpawnGroupsRow(
        spawn_group_id:,
        reset_freq:,
        is_enabled:,
        is_despawn_on_reset:,
      ) = group

      world.SpawnGroup(
        id: Id(spawn_group_id),
        reset_freq:,
        is_enabled:,
        is_despawn_on_reset:,
        mob_members: dict.get(mob_spawns, spawn_group_id) |> result.unwrap([]),
        item_members: dict.get(item_spawns, spawn_group_id) |> result.unwrap([]),
        mob_instances: [],
        item_instances: [],
      )
    })

  list.map(zones, fn(zone) {
    world.Zone(
      id: world.Id(zone.zone_id),
      name: zone.name,
      rooms:,
      spawn_groups:,
    )
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
