//// Supervisor for named Erlang Term Storage (ETS) tables.
//// 

import gleam/erlang/process
import gleam/otp/static_supervisor.{add}
import gleam/otp/supervision.{worker}
import lore/character/character_registry
import lore/character/users
import lore/world/communication
import lore/world/items
import lore/world/mapper
import lore/world/room/presence
import lore/world/room/room_registry
import lore/world/zone/zone_registry

/// Record for looking up a registry name created at runtime.
/// 
/// Given a registry name, we can perform a lookup in the table from the caller
/// without message passing.
/// 
pub type Lookup {
  /// - ZoneRegistry: Looks up Zone subjects
  /// - RoomRegistry: ..RoomSubjects
  /// - CharacterRegistry: ..Character Subjects
  /// - Communication: ..Communication channels with lists of subscribers
  /// - Presence: Tracks the room_id that a mobile is present in
  /// - Users: Get connected user information
  /// - Mapper: Generate ascii maps
  /// - Items: A table for exposing item data by id
  /// 
  Lookup(
    zone: process.Name(zone_registry.Message),
    room: process.Name(room_registry.Message),
    character: process.Name(character_registry.Message),
    communication: process.Name(communication.Message),
    presence: process.Name(presence.Message),
    users: process.Name(users.Message),
    mapper: process.Name(mapper.Message),
    items: process.Name(items.Message),
  )
}

/// Starts the table supervisor.
/// 
pub fn supervised(
  name: Lookup,
) -> supervision.ChildSpecification(static_supervisor.Supervisor) {
  static_supervisor.new(static_supervisor.OneForOne)
  |> add(worker(fn() { zone_registry.start(name.zone) }))
  |> add(worker(fn() { room_registry.start(name.room) }))
  |> add(worker(fn() { character_registry.start(name.character) }))
  |> add(worker(fn() { communication.start(name.communication) }))
  |> add(worker(fn() { presence.start(name.presence, name.room) }))
  |> add(worker(fn() { users.start(name.users, name.communication) }))
  |> static_supervisor.supervised
}
