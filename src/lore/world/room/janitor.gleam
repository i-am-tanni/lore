//// An actor that tracks dropped items and periodically cleans them up.
//// Checks every ten minutes at fixed, hour-aligned intervals if there is
//// anything to despawn.
////

import gleam/dict
import gleam/erlang/process
import gleam/float
import gleam/int
import gleam/list
import gleam/order
import gleam/otp/actor
import gleam/result
import gleam/time/duration
import gleam/time/timestamp.{type Timestamp}
import lore/server/my_list
import lore/world.{type Id, type ItemInstance, type Room, type StringId}
import lore/world/event
import lore/world/room/room_registry

// Check every 10 minutes at fixed, hour-aligned intervals
const check_every_ms = 600_000

pub type Message {
  Track(
    item_id: StringId(ItemInstance),
    location: Id(Room),
    destroy_at: Timestamp,
  )
  Untrack(item_id: StringId(ItemInstance))
  Clean(Timestamp)
}

type ItemTracked {
  ItemTracked(
    item_id: StringId(ItemInstance),
    location: Id(Room),
    destroy_at: Timestamp,
  )
}

type State {
  State(
    self: process.Subject(Message),
    room_registry: process.Name(room_registry.Message),
    sorted: List(ItemTracked),
  )
}

/// Start janitor actor so it can track dropped items and remove them
/// before the world gets cluttered with trash.
///
pub fn start(
  name: process.Name(Message),
  room_registry: process.Name(room_registry.Message),
) -> Result(actor.Started(process.Subject(Message)), actor.StartError) {
  actor.new_with_initialiser(500, init(_, room_registry))
  |> actor.named(name)
  |> actor.on_message(recv)
  |> actor.start
}

fn init(
  self: process.Subject(Message),
  room_registry: process.Name(room_registry.Message),
) -> Result(actor.Initialised(State, Message, process.Subject(Message)), String) {
  schedule_next_cleanup(self)

  State(self:, sorted: [], room_registry:)
  |> actor.initialised
  |> actor.returning(self)
  |> Ok
}

/// Track the item and clean up as scheduled.
/// This typically is called when an item is dropped.
///
pub fn track_item(
  name: process.Name(Message),
  item_id: StringId(ItemInstance),
  location: Id(Room),
  destroy_at: Timestamp,
) -> Nil {
  process.named_subject(name)
  |> actor.send(Track(item_id:, location:, destroy_at:))
}

/// Remove tracking on an item.
/// This is typically called when an item is picked up.
///
pub fn untrack_item(
  name: process.Name(Message),
  item: StringId(ItemInstance),
) -> Nil {
  process.named_subject(name)
  |> actor.send(Untrack(item))
}

fn recv(state: State, msg: Message) -> actor.Next(State, Message) {
  let state = case msg {
    Track(item_id:, location:, destroy_at:) -> {
      let update =
        ItemTracked(item_id:, location:, destroy_at:)
        |> my_list.insert_when(state.sorted, _, fn(a, b) {
          // insert into list in ascending order
          timestamp.compare(a.destroy_at, b.destroy_at) == order.Gt
        })

      State(..state, sorted: update)
    }

    Untrack(id) -> {
      let filtered =
        list.filter(state.sorted, fn(tracking) { tracking.item_id != id })
      State(..state, sorted: filtered)
    }

    Clean(timestamp) -> {
      let #(to_destroy, sorted) =
        list.split_while(state.sorted, fn(tracking) {
          // list is sorted in ascending order by destroy_at timestamp
          // split at timestamp
          timestamp.compare(tracking.destroy_at, timestamp) != order.Gt
        })

      despawn_items(to_destroy, state.room_registry)
      schedule_next_cleanup(state.self)
      State(..state, sorted:)
    }
  }

  actor.continue(state)
}

fn despawn_items(
  to_destroy: List(ItemTracked),
  room_registry: process.Name(room_registry.Message),
) -> Nil {
  my_list.group_by(to_destroy, fn(tracked) {
    #(tracked.location, tracked.item_id)
  })
  |> dict.to_list
  |> list.each(fn(pair) {
    let #(room_id, items_to_despawn) = pair
    case room_registry.whereis(room_registry, room_id) {
      Ok(room_subject) ->
        actor.send(room_subject, event.DespawnItems(items_to_despawn))

      Error(_) -> Nil
    }
  })
}

fn schedule_next_cleanup(self: process.Subject(Message)) -> process.Timer {
  let now = timestamp.system_time()

  let delay_in_ms =
    now
    |> timestamp.to_unix_seconds
    |> fn(x) { float.truncate(x *. 1000.0) }
    |> int.modulo(check_every_ms)
    |> result.unwrap(0)
    |> int.subtract(check_every_ms, _)

  process.send_after(
    self,
    delay_in_ms,
    Clean(timestamp.add(now, duration.milliseconds(delay_in_ms))),
  )
}
