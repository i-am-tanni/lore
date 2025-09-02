import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import glets/cache
import lore/world.{type Id, type Room}
import lore/world/event.{type RoomMessage}

/// A message received by the registry process to insert the room subject
/// into the cache keyed by the room instance id.
/// 
pub type Message =
  cache.Message(Id(Room), Subject(RoomMessage))

/// Starts the room subject registry.
/// 
pub fn start(
  table_name: process.Name(Message),
) -> Result(actor.Started(process.Subject(Message)), actor.StartError) {
  cache.start(table_name)
}

/// Registers as list of room subjects keyed by their room instance id
/// 
pub fn register(
  table_name: process.Name(Message),
  room_id: Id(Room),
  subject: process.Subject(RoomMessage),
) -> Nil {
  table_name
  |> process.named_subject
  |> process.send(cache.Insert(room_id, subject))
}

pub fn deregister(table_name: process.Name(Message), room_id: Id(Room)) {
  process.named_subject(table_name)
  |> process.send(cache.Delete(room_id))
}

/// Returns the subject given a registered room instance id.
/// 
pub fn whereis(
  table_name: process.Name(Message),
  room_id: Id(Room),
) -> Result(process.Subject(RoomMessage), Nil) {
  cache.lookup(table_name, room_id)
}
