import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import ming/server/cache
import ming/world.{type Zone, type ZoneMessage}
import ming/world/id.{type Id, Id}

const table_name = "zone_registry"

/// A message received by the registry process to insert the room subject
/// into the cache keyed by the room instance id.
/// 
pub type Register =
  cache.Message(Id(Zone), Subject(ZoneMessage))

/// Starts the room process registry.
/// 
pub fn start() -> Result(
  Subject(cache.Message(Id(Zone), Subject(ZoneMessage))),
  actor.StartError,
) {
  cache.start(table_name, cache.recv)
}

/// Registers as list of room subjects keyed by their room instance id
/// 
pub fn register(
  objects: List(#(Id(Zone), Subject(ZoneMessage))),
  registry: Subject(cache.Message(Id(Zone), Subject(ZoneMessage))),
) {
  process.send(registry, cache.Insert(objects))
}

/// Returns the subject given a registered room instance id.
/// 
pub fn whereis(room_id: Id(Zone)) -> Result(Subject(ZoneMessage), Nil) {
  cache.lookup(table_name, room_id)
}
