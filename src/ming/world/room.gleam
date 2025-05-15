/// An actor for a room process, which serves as a synchronization point
/// for physical actions and tracks the room state.
/// 
import gleam/erlang/process.{type Subject}
import gleam/function
import gleam/otp/actor
import ming/world.{type Room, type RoomMessage}
import ming/world/id.{type Id}
import ming/world/room/context.{type Context}
import ming/world/room/room_registry

/// Starts a room and registers it.
/// 
pub fn start(
  room: Room,
  registry: Subject(room_registry.Register),
) -> Result(Subject(RoomMessage), actor.StartError) {
  let spec =
    actor.Spec(init: fn() { init(room, registry) }, init_timeout: 5, loop: recv)

  actor.start_spec(spec)
}

fn init(
  state: Room,
  registry: Subject(room_registry.Register),
) -> actor.InitResult(Room, RoomMessage) {
  let self = process.new_subject()
  room_registry.register([#(state.id, self)], registry)

  let selector =
    process.new_selector()
    |> process.selecting(self, function.identity)

  actor.Ready(state, selector)
}

fn recv(_msg: RoomMessage, room: Room) -> actor.Next(RoomMessage, Room) {
  actor.continue(room)
}

pub fn whereis(room_id: Id(Room)) -> Result(Subject(RoomMessage), Nil) {
  room_registry.whereis(room_id)
}
