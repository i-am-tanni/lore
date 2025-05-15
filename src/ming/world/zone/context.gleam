import gleam/erlang/process.{type Subject}
import ming/world.{type Zone}
import ming/world/room/presence

pub type Context {
  Context(zone: Zone, presence: Subject(presence.Insert))
}

pub fn new(zone: Zone, presence: Subject(presence.Insert)) -> Context {
  Context(zone: zone, presence: presence)
}
