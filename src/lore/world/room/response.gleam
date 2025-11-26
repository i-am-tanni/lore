//// A module for building responses to received room events.
////

import gleam/bool
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import lore/character/view.{type View}
import lore/server/my_list
import lore/server/output
import lore/world.{
  type Id, type ItemInstance, type Mobile, type RoomExit, type StringId,
  type Zone,
}
import lore/world/communication.{type Channel, RoomChannel}
import lore/world/event.{
  type CharacterEvent, type CharacterMessage, type Event, type RoomMessage,
  type RoomToRoomEvent, type ZoneEvent,
}
import lore/world/mapper
import lore/world/system_tables

/// A builder for a response to a room event.
/// Brings in context from the event (caller & acting_character) and the room
/// data.
///
pub opaque type Builder(a) {
  Builder(
    room: world.Room,
    caller: Subject(a),
    self: Subject(RoomMessage),
    acting_character: Option(world.Mobile),
    system_tables: system_tables.Lookup,
    output: List(#(Subject(CharacterMessage), output.Text)),
    events: List(EventToSend(a)),
    update_characters: Option(List(Mobile)),
    update_items: Option(List(ItemInstance)),
    update_exits: Option(List(RoomExit)),
    combat_queue: List(event.CombatPollData),
    is_in_combat: Bool,
  )
}

/// A completed response to an request received by the room.
///
pub type Response(a) {
  Response(
    events: List(EventToSend(a)),
    output: List(#(Subject(CharacterMessage), output.Text)),
    update_characters: Option(List(Mobile)),
    update_items: Option(List(ItemInstance)),
    update_exits: Option(List(RoomExit)),
    combat_queue: List(event.CombatPollData),
    is_in_combat: Bool,
  )
}

/// Events are queued and processed after the response is fully built.
/// Events are tagged by recipient.
///
pub type EventToSend(a) {
  /// Reply to the author of an event asychronously.
  ///
  Reply(to: Subject(a), message: a)
  /// Send an event to an individual character.
  ///
  ToCharacter(
    subject: Subject(CharacterMessage),
    event: Event(CharacterEvent, RoomMessage),
  )
  /// Send an event to an individual character when the subject is unknown
  ///
  ToCharacterId(id: StringId(Mobile), event: Event(CharacterEvent, RoomMessage))

  /// Broadcast an event to all subscribers in the room channel
  ///
  Broadcast(channel: Channel, event: Event(CharacterEvent, RoomMessage))

  /// A subscription to channel messages
  ///
  Subscribe(channel: Channel, subscriber: communication.Subscriber)

  /// Unsubscribe from channel messages
  ///
  Unsubscribe(channel: Channel, subscriber: communication.Subscriber)

  ToRoom(id: Id(world.Room), event: Event(RoomToRoomEvent, RoomMessage))
  /// Send an event to the zone.
  ///
  ToZone(id: Id(Zone), event: Event(event.ZoneEvent, RoomMessage))
}

/// Create a new response builder.
/// Arguments are the context for the builder.
///
pub fn new(
  room: world.Room,
  caller: Subject(a),
  self: Subject(RoomMessage),
  acting_character: Option(world.Mobile),
  system_tables: system_tables.Lookup,
  combat_queue: List(event.CombatPollData),
  is_in_combat: Bool,
) -> Builder(a) {
  Builder(
    room:,
    caller:,
    self:,
    acting_character:,
    system_tables:,
    output: [],
    events: [],
    update_characters: None,
    update_items: None,
    update_exits: None,
    combat_queue:,
    is_in_combat:,
  )
}

pub fn room(builder: Builder(a)) -> world.Room {
  builder.room
}

/// Returns room subject.
///
pub fn self(builder: Builder(a)) -> Subject(RoomMessage) {
  builder.self
}

pub fn system_tables(builder: Builder(a)) -> system_tables.Lookup {
  builder.system_tables
}

pub fn is_in_combat(builder: Builder(a)) -> Bool {
  builder.is_in_combat
}

pub fn combat_commence(
  builder: Builder(a),
  acting_character: world.Mobile,
) -> Builder(a) {
  use <- bool.guard(builder.is_in_combat, builder)
  Builder(..builder, is_in_combat: True)
  |> broadcast(acting_character, event.CombatRoundPoll)
}

pub fn combat_end(builder: Builder(a)) -> Builder(a) {
  Builder(..builder, is_in_combat: False)
}

/// Get the mini_map via a call
///
pub fn mini_map(builder: Builder(a)) {
  mapper.render_mini_map(builder.system_tables.mapper, builder.room.id)
}

/// Finds a local exit based on the given boolean function.
///
pub fn find_local_exit(
  builder: Builder(a),
  matcher: fn(RoomExit) -> Bool,
) -> Result(RoomExit, Nil) {
  list.find(builder.room.exits, matcher)
}

/// Finds a local character based on the given boolean function.
///
pub fn find_local_character(
  builder: Builder(a),
  search_fun: fn(Mobile) -> Bool,
) -> Result(Mobile, world.ErrorRoomRequest) {
  let characters = case builder.update_characters {
    Some(updates) -> updates
    None -> builder.room.characters
  }

  my_list.find_nth(characters, 0, search_fun)
  |> result.replace_error(world.CharacterLookupFailed)
}

/// Finds a local item based on the given boolean function.
///
pub fn find_local_item(
  builder: Builder(a),
  search_term: String,
) -> Result(world.ItemInstance, world.ErrorRoomRequest) {
  {
    use item <- my_list.find_nth(builder.room.items, 0)
    use keyword <- list.any(item.keywords)
    search_term == keyword
  }
  |> result.replace_error(world.ItemLookupFailed(search_term))
}

/// Finds a local items based on the given boolean function.
///
pub fn find_local_items(
  builder: Builder(a),
  up_to amount: Int,
  many_that is_desired: fn(world.ItemInstance) -> Bool,
) -> List(ItemInstance) {
  builder.room.items
  |> list.filter(is_desired)
  |> list.take(amount)
}

/// Queue an event to the queue to be fired off in order when response is
/// completed.
///
pub fn event(builder: Builder(a), event: EventToSend(a)) -> Builder(a) {
  Builder(..builder, events: [event, ..builder.events])
}

/// Queues a zone event
///
pub fn zone_event(
  builder: Builder(a),
  event: Event(ZoneEvent, RoomMessage),
) -> Builder(a) {
  let event_to_send = ToZone(builder.room.zone_id, event)
  Builder(..builder, events: [event_to_send, ..builder.events])
}

/// Queues a character event
///
pub fn character_event(
  builder: Builder(a),
  event: CharacterEvent,
  from acting_character: world.Mobile,
  to recipient: world.StringId(Mobile),
) -> Builder(a) {
  let event_to_send =
    event.Event(from: builder.self, acting_character:, data: event)
    |> ToCharacterId(id: recipient, event: _)

  Builder(..builder, events: [event_to_send, ..builder.events])
}

/// Respond directly to the caller of the event.
///
pub fn reply(builder: Builder(a), msg: a) -> Builder(a) {
  Builder(..builder, events: [Reply(builder.caller, msg), ..builder.events])
}

/// Respond to the character that generated the room request.
///
pub fn reply_character(
  builder: Builder(CharacterMessage),
  data: event.CharacterEvent,
) -> Builder(CharacterMessage) {
  case builder.acting_character {
    Some(acting_character) -> {
      let event = event.new(from: builder.self, acting_character:, data:)
      Builder(..builder, events: [
        ToCharacter(builder.caller, event),
        ..builder.events
      ])
    }

    None -> builder
  }
}

/// Convert the response builder to a response to be processed by the room.
///
pub fn build(builder: Builder(a)) -> Response(a) {
  Response(
    events: list.reverse(builder.events),
    // we don't reverse the output list because we're going to reverse it later
    output: builder.output,
    update_characters: builder.update_characters,
    update_items: builder.update_items,
    update_exits: builder.update_exits,
    combat_queue: builder.combat_queue,
    is_in_combat: builder.is_in_combat,
  )
}

/// Queue an Event to be broadcasted to all subscribers of the room
/// channel. This is useful for witnessed events.
///
pub fn broadcast_event(
  builder: Builder(a),
  event event: Event(CharacterEvent, RoomMessage),
) -> Builder(a) {
  let queued_event = Broadcast(RoomChannel(builder.room.id), event)
  Builder(..builder, events: [queued_event, ..builder.events])
}

/// Queue a CharacterEvent to be broadcasted to all subscribers of the room
/// channel. This is useful for witnessed events.
///
pub fn broadcast(
  builder: Builder(a),
  acting_character: world.Mobile,
  event: CharacterEvent,
) -> Builder(a) {
  let queued_event =
    event.Event(data: event, acting_character:, from: builder.self)
    |> Broadcast(RoomChannel(builder.room.id), _)

  Builder(..builder, events: [queued_event, ..builder.events])
}

/// Subscribe to room events
///
pub fn subscribe_character(
  builder: Builder(a),
  subject: Subject(CharacterMessage),
) -> Builder(a) {
  let subscriber = communication.Mobile(subject)
  let queued_event = Subscribe(RoomChannel(builder.room.id), subscriber)
  Builder(..builder, events: [queued_event, ..builder.events])
}

/// Unsubscribe from room events
///
pub fn unsubscribe_character(
  builder: Builder(a),
  subject: Subject(CharacterMessage),
) -> Builder(a) {
  let subscriber = communication.Mobile(subject)
  let queued_event = Unsubscribe(RoomChannel(builder.room.id), subscriber)
  Builder(..builder, events: [queued_event, ..builder.events])
}

/// Render text back to the subject of the event.
///
pub fn render(
  builder: Builder(CharacterMessage),
  view: View,
) -> Builder(CharacterMessage) {
  render_to(builder, builder.caller, view)
}

/// Render text back to the subject of the event and append with a newline.
///
pub fn renderln(
  builder: Builder(CharacterMessage),
  view: View,
) -> Builder(CharacterMessage) {
  renderln_to(builder, builder.caller, view)
}

/// Render text to a subject.
///
pub fn render_to(
  builder: Builder(a),
  to subject: Subject(CharacterMessage),
  via view: View,
) -> Builder(a) {
  let output = output.Text(text: view.to_string_tree(view), newline: False)
  Builder(..builder, output: [#(subject, output), ..builder.output])
}

/// Render text to a subject with a newline.
///
pub fn renderln_to(
  builder: Builder(a),
  to subject: Subject(CharacterMessage),
  via view: View,
) -> Builder(a) {
  let output = output.Text(text: view.to_string_tree(view), newline: True)
  Builder(..builder, output: [#(subject, output), ..builder.output])
}

pub fn exits_update(
  builder: Builder(a),
  exits: List(world.RoomExit),
) -> Builder(a) {
  Builder(..builder, update_exits: Some(exits))
}

/// Insert a character into the room.
///
pub fn character_insert(
  builder: Builder(a),
  character: world.Mobile,
) -> Builder(a) {
  let characters = case builder.update_characters {
    Some(updated) -> updated
    None -> builder.room.characters
  }
  Builder(..builder, update_characters: Some([character, ..characters]))
}

/// Delete a character from the room.
///
pub fn character_delete(
  builder: Builder(a),
  character: world.Mobile,
) -> Builder(a) {
  let characters = case builder.update_characters {
    Some(updated) -> updated
    None -> builder.room.characters
  }
  let mobile_id = character.id
  let filtered = list.filter(characters, fn(mobile) { mobile.id != mobile_id })
  Builder(..builder, update_characters: Some(filtered))
}

/// Updates a character in the room.
///
pub fn character_update(
  builder: Builder(a),
  updated_character: world.Mobile,
) -> Builder(a) {
  let characters = case builder.update_characters {
    Some(updated) -> updated
    None -> builder.room.characters
  }
  let update =
    list.map(characters, fn(mobile) {
      case mobile.id == updated_character.id {
        True -> updated_character
        False -> mobile
      }
    })

  Builder(..builder, update_characters: Some(update))
}

pub fn characters_put(
  builder: Builder(a),
  updated_characters: List(world.Mobile),
) -> Builder(a) {
  Builder(..builder, update_characters: Some(updated_characters))
}

/// Insert an item into the room.
///
pub fn item_insert(builder: Builder(a), item: ItemInstance) -> Builder(a) {
  let items = builder.room.items
  Builder(..builder, update_items: Some([item, ..items]))
}

/// Delete an item from the room.
///
pub fn item_delete(builder: Builder(a), item: ItemInstance) -> Builder(a) {
  let items = builder.room.items
  let instance_id = item.id
  let filtered = list.filter(items, fn(item) { item.id != instance_id })
  Builder(..builder, update_items: Some(filtered))
}

/// Pushes a round-based combat action into the queue
///
pub fn round_push(
  builder: Builder(a),
  combat_data: event.CombatPollData,
) -> Builder(a) {
  Builder(..builder, combat_queue: [combat_data, ..builder.combat_queue])
}

pub fn round_flush(
  builder: Builder(a),
) -> #(List(event.CombatPollData), Builder(a)) {
  let combat_queue = builder.combat_queue
  #(combat_queue, Builder(..builder, combat_queue: []))
}
