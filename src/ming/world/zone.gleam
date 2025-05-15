import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import ming/world.{
  type Event, type RoomMessage, type Zone, type ZoneEvent, type ZoneMessage,
  Event, MoveKickoff,
}
import ming/world/id.{type Id}
import ming/world/room/presence
import ming/world/zone/context.{type Context}
import ming/world/zone/events/move_event
import ming/world/zone/zone_registry

pub type State {
  State(zone: Zone, presence: Subject(presence.Insert))
}

pub fn recv(
  event: Event(ZoneEvent, RoomMessage),
  state: State,
) -> actor.Next(ZoneMessage, State) {
  let _ = case event.data {
    MoveKickoff(..) -> move_event.process(new_context(state), event)
    _ -> todo
  }

  actor.continue(state)
}

pub fn new_context(state: State) -> Context {
  context.new(state.zone, state.presence)
}

pub fn whereis(id: Id(Zone)) -> Result(Subject(ZoneMessage), Nil) {
  zone_registry.whereis(id)
}
