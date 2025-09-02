import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import glets/cache
import lore/world.{type Id, type Zone}
import lore/world/event.{type ZoneMessage}

/// A message received by the registry process to insert the room subject
/// into the cache keyed by the room instance id.
/// 
pub type Message =
  cache.Message(Id(Zone), Subject(ZoneMessage))

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
  zone_id: Id(Zone),
  subject: process.Subject(ZoneMessage),
) -> Nil {
  table_name
  |> process.named_subject
  |> process.send(cache.Insert(zone_id, subject))
}

/// Returns the subject given a registered room instance id.
/// 
pub fn whereis(
  table_name: process.Name(Message),
  zone_id: Id(Zone),
) -> Result(process.Subject(ZoneMessage), Nil) {
  cache.lookup(table_name, zone_id)
}
