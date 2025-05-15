import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import ming/server/cache
import ming/world.{type CharacterMessage, type Mobile}
import ming/world/id.{type Id, Id}

const table_name = "mob_registry"

/// A message received by the registry process to insert the room subject
/// into the cache keyed by the room instance id.
/// 
pub type Register =
  cache.Message(Id(Mobile), Subject(CharacterMessage))

/// Starts the room process registry.
/// 
pub fn start() -> Result(
  Subject(cache.Message(Id(Mobile), Subject(CharacterMessage))),
  actor.StartError,
) {
  cache.start(table_name, cache.recv)
}

/// Registers as list of room subjects keyed by their room instance id
/// 
pub fn register(
  objects: List(#(Id(Mobile), Subject(CharacterMessage))),
  registry: Subject(cache.Message(Id(Mobile), Subject(CharacterMessage))),
) {
  process.send(registry, cache.Insert(objects))
}

pub fn unregister(
  key: Id(Mobile),
  registry: Subject(cache.Message(Id(Mobile), Subject(CharacterMessage))),
) {
  process.send(registry, cache.Delete(key))
}

/// Returns the subject given a registered room instance id.
/// 
pub fn whereis(room_id: Id(Mobile)) -> Result(Subject(CharacterMessage), Nil) {
  cache.lookup(table_name, room_id)
}
