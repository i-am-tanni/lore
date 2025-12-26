//// An actor that tracks dropped items and periodically cleans them up.
//// Checks every at fixed, hour-aligned intervals if there is
//// anything to despawn.
////

import gleam/dict.{type Dict}
import gleam/erlang/process
import gleam/float
import gleam/int
import gleam/list
import gleam/otp/actor
import gleam/result
import gleam/time/duration
import gleam/time/timestamp.{type Timestamp}
import lore/server/my_list
import lore/world.{type Id, type ItemInstance, type Room, type StringId}
import lore/world/event
import lore/world/room/room_registry

// Check every 10 minutes at fixed, hour-aligned intervals
const check_every_x_seconds = 600

pub type Message {
  /// Add tracking and send despawn message to location
  /// when destroy_at time is exceeded.
  ///
  Track(
    item_id: StringId(ItemInstance),
    location: Id(Room),
    destroy_at: Timestamp,
  )

  /// Remove tracking.
  ///
  Untrack(item_id: StringId(ItemInstance))

  /// Check if there are any items due for clean up.
  ///
  Clean(Timestamp)
}

type ItemTracked {
  ItemTracked(
    item_id: StringId(ItemInstance),
    location: Id(Room),
    destroy_at: Timestamp,
  )
}

type Tracking {
  Tracking(
    clean_up_blocks: Dict(Timestamp, List(ItemTracked)),
    block_lookup: Dict(StringId(ItemInstance), Timestamp),
  )
}

/// Internally the tracked items are stored in a dict keyed by their clean up
/// timestamp, which is arranged in fixed interval blocks. Keys are tracked
/// in a separate dictionary.
///
type State {
  State(
    self: process.Subject(Message),
    room_registry: process.Name(room_registry.Message),
    tracking: Tracking,
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
  let tracking = Tracking(clean_up_blocks: dict.new(), block_lookup: dict.new())

  State(self:, tracking:, room_registry:)
  |> actor.initialised
  |> actor.returning(self)
  |> Ok
}

/// Track the item and clean up as scheduled.
/// This typically is called when an item is dropped.
///
pub fn item_schedule_clean_up(
  name: process.Name(Message),
  what item_id: StringId(ItemInstance),
  at location: Id(Room),
  in duration: duration.Duration,
) -> Nil {
  let destroy_at = timestamp.system_time() |> timestamp.add(duration)

  process.named_subject(name)
  |> actor.send(Track(item_id:, location:, destroy_at:))
}

/// Remove tracking on an item.
/// This is typically called when an item is picked up.
///
pub fn item_cancel_clean_up(
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
        |> track_item_instance(state.tracking)

      State(..state, tracking: update)
    }

    Untrack(item_id) -> {
      case untrack_item_instance(state.tracking, item_id) {
        Ok(update) -> State(..state, tracking: update)
        Error(_) -> state
      }
    }

    Clean(cutoff) -> {
      let tracking = clean_up(state.tracking, cutoff, state.room_registry)
      schedule_next_cleanup(state.self)
      State(..state, tracking:)
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
  let now =
    timestamp.system_time()
    |> timestamp.to_unix_seconds
    |> float.truncate

  let delay_in_seconds =
    now
    |> int.modulo(check_every_x_seconds)
    |> result.unwrap(0)
    |> int.subtract(check_every_x_seconds, _)

  let next = timestamp.from_unix_seconds(now + delay_in_seconds)

  process.send_after(self, delay_in_seconds * 1000, Clean(next))
}

fn clean_up_time(destroy_at: Timestamp) -> Timestamp {
  let destroy_at =
    destroy_at
    |> timestamp.to_unix_seconds
    |> float.truncate

  destroy_at
  |> int.modulo(check_every_x_seconds)
  |> result.unwrap(0)
  |> int.subtract(check_every_x_seconds, _)
  |> int.add(destroy_at)
  |> timestamp.from_unix_seconds
}

fn track_item_instance(
  item_tracked: ItemTracked,
  tracking: Tracking,
) -> Tracking {
  let Tracking(clean_up_blocks:, block_lookup:) = tracking
  let block = clean_up_time(item_tracked.destroy_at)
  let clean_up_list =
    dict.get(clean_up_blocks, block)
    |> result.unwrap([])
    |> list.prepend(item_tracked)

  Tracking(
    clean_up_blocks: dict.insert(clean_up_blocks, block, clean_up_list),
    block_lookup: dict.insert(block_lookup, item_tracked.item_id, block),
  )
}

fn untrack_item_instance(
  tracking: Tracking,
  item_id: StringId(ItemInstance),
) -> Result(Tracking, Nil) {
  let Tracking(clean_up_blocks:, block_lookup:) = tracking
  use timestamp <- result.try(dict.get(block_lookup, item_id))
  use clean_up_list <- result.try(dict.get(clean_up_blocks, timestamp))
  let filtered =
    list.filter(clean_up_list, fn(item_tracked) {
      item_tracked.item_id != item_id
    })

  case filtered {
    [_, ..] ->
      Tracking(
        clean_up_blocks: dict.insert(clean_up_blocks, timestamp, filtered),
        block_lookup: dict.delete(block_lookup, item_id),
      )

    [] ->
      Tracking(
        clean_up_blocks: dict.delete(clean_up_blocks, timestamp),
        block_lookup: dict.delete(block_lookup, item_id),
      )
  }
  |> Ok
}

fn clean_up(
  tracking: Tracking,
  cutoff: Timestamp,
  room_registry: process.Name(room_registry.Message),
) -> Tracking {
  let Tracking(clean_up_blocks:, block_lookup:) = tracking
  let clean_up_list =
    dict.get(clean_up_blocks, cutoff)
    |> result.unwrap([])

  despawn_items(clean_up_list, room_registry)

  let block_lookup =
    list.map(clean_up_list, fn(tracked) { tracked.item_id })
    |> dict.drop(block_lookup, _)

  Tracking(clean_up_blocks: dict.delete(clean_up_blocks, cutoff), block_lookup:)
}
