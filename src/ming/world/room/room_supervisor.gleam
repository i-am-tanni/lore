import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/otp/actor
import gleam/otp/supervisor
import ming/world.{type Room}
import ming/world/room
import ming/world/room/room_registry

pub fn start(
  rooms: List(Room),
  room_registry: Subject(room_registry.Register),
) -> Result(Subject(supervisor.Message), actor.StartError) {
  let workers =
    list.map(rooms, fn(room) {
      supervisor.worker(fn(_) { room.start(room, room_registry) })
    })

  supervisor.start(fn(children) { list.fold(workers, children, supervisor.add) })
}
