//// Presence is an ets table that simply tracks which room a character is in.
//// 

import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import ming/server/cache
import ming/world.{type Mobile, type Room}
import ming/world/id.{type Id, Id}

const table_name = "presence"

pub type Insert =
  cache.Message(Id(Mobile), Id(Room))

/// Starts the presence table.
/// 
pub fn start() -> Result(
  Subject(cache.Message(Id(Mobile), Id(Room))),
  actor.StartError,
) {
  cache.start(table_name, cache.recv)
}

/// Request the room id given a mobile id.
/// 
pub fn whereis(character: Id(Mobile)) -> Result(Id(Room), Nil) {
  cache.lookup(table_name, character)
}

pub fn insert(
  subject: Subject(cache.Message(Id(Mobile), Id(Room))),
  character_id: Id(Mobile),
  room_id: Id(Room),
) -> Nil {
  process.send(subject, cache.Insert([#(character_id, room_id)]))
}
