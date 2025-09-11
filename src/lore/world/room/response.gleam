//// A module for building responses to received room events.
//// 

import gleam/dict
import gleam/erlang/process.{type Subject}
import gleam/function
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import lore/character/character_registry
import lore/character/view.{type View}
import lore/server/my_list
import lore/server/output
import lore/world.{
  type Id, type ItemInstance, type Mobile, type RoomExit, type StringId,
  type Zone, Room,
}
import lore/world/communication.{type Channel, RoomChannel}
import lore/world/event.{
  type CharacterEvent, type CharacterMessage, type Event, type RoomMessage,
  type RoomToRoomEvent, type ZoneEvent,
}
import lore/world/mapper
import lore/world/room/room_registry
import lore/world/system_tables
import lore/world/zone/zone_registry

/// A builder for a response to a room event.
/// Brings in context from the event (caller & acting_character) and the room
/// data.
/// 
pub opaque type Builder(a) {
  Builder(
    room: world.Room,
    caller: Subject(a),
    self: Subject(RoomMessage),
    system_tables: system_tables.Lookup,
    output: List(#(Subject(CharacterMessage), output.Text)),
    events: List(EventToSend(a)),
    update_characters: Option(List(Mobile)),
    update_items: Option(List(ItemInstance)),
    update_exits: Option(List(RoomExit)),
  )
}

/// A completed response to an request received by the room.
/// 
pub opaque type Response(a) {
  Response(
    events: List(EventToSend(a)),
    output: List(#(Subject(CharacterMessage), output.Text)),
    update_characters: Option(List(Mobile)),
    update_items: Option(List(ItemInstance)),
    update_exits: Option(List(RoomExit)),
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
  system_tables: system_tables.Lookup,
) -> Builder(a) {
  Builder(
    room:,
    caller:,
    self:,
    system_tables:,
    output: [],
    events: [],
    update_characters: None,
    update_items: None,
    update_exits: None,
  )
}

/// Exposes the context of the event including:
/// - `room` data
/// - 'caller' - i.e. the mailbox of who sent the event
/// - `acting_character` - the character information of the event sender
/// 
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
  search_term: String,
) -> Result(Mobile, world.ErrorRoomRequest) {
  {
    use character <- my_list.find_nth(builder.room.characters, 0)
    use keyword <- list.any(character.keywords)
    search_term == keyword
  }
  |> result.replace_error(world.CharacterLookupFailed(search_term))
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
  acting_character: world.Mobile,
  recipient: world.StringId(Mobile),
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
  event: Event(event.CharacterToRoomEvent, CharacterMessage),
  data: event.CharacterEvent,
) -> Builder(CharacterMessage) {
  let acting_character = event.acting_character
  let event = event.new(from: builder.self, acting_character:, data:)
  Builder(..builder, events: [
    ToCharacter(builder.caller, event),
    ..builder.events
  ])
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
  )
}

/// Queue a CharacterEvent to be broadcasted to all subscribers of the room
/// channel. This is useful for witnessed events.
/// 
pub fn broadcast(
  builder: Builder(a),
  event event: Event(CharacterEvent, RoomMessage),
) -> Builder(a) {
  let queued_event = Broadcast(RoomChannel(builder.room.id), event)
  Builder(..builder, events: [queued_event, ..builder.events])
}

pub fn broadcast_action(
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
  let characters = builder.room.characters
  Builder(..builder, update_characters: Some([character, ..characters]))
}

/// Delete a character from the room.
/// 
pub fn character_delete(
  builder: Builder(a),
  character: world.Mobile,
) -> Builder(a) {
  let characters = builder.room.characters
  let mobile_id = character.id
  let filtered = list.filter(characters, fn(mobile) { mobile.id != mobile_id })
  Builder(..builder, update_characters: Some(filtered))
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

/// Process a response to a RoomEvent and commit staged state changes.
/// 
pub fn handle_response(
  response: Response(a),
  room: world.Room,
  system_tables: system_tables.Lookup,
) -> world.Room {
  // Send outputs
  send_text(response.output, room)
  list.each(response.events, send_event(_, room, system_tables))

  // update room state
  let Response(update_characters:, update_items:, update_exits:, ..) = response
  let items = case update_items {
    Some(items_update) -> items_update
    None -> room.items
  }

  let characters = case update_characters {
    Some(characters_update) -> characters_update
    None -> room.characters
  }

  let exits = case update_exits {
    Some(exits_update) -> exits_update
    None -> room.exits
  }

  Room(..room, characters:, items:, exits:)
}

fn send_text(
  output: List(#(Subject(CharacterMessage), output.Text)),
  from room: world.Room,
) -> Nil {
  case output {
    // if the list is empty, do nothing
    //
    [] -> Nil
    // ...otherwise if the list only has one message to send, send that
    //
    [#(subject, output)] -> {
      let text = event.RoomSentText(text: [output])
      process.send(subject, event.RoomSent(text, room.id))
    }
    // ...and if the list has more than one member, group by subject, reverse
    // the order, and send as a batch
    //
    _ -> {
      let room_id = room.id

      my_list.group_by(output, function.identity)
      |> dict.to_list
      |> list.each(fn(pair) {
        let #(subject, outputs) = pair
        let text = event.RoomSentText(text: outputs)
        process.send(subject, event.RoomSent(text, room_id))
      })
    }
  }
}

fn send_event(
  event: EventToSend(a),
  from room: world.Room,
  lookup system_tables: system_tables.Lookup,
) -> Nil {
  case event {
    Reply(to:, message:) -> process.send(to, message)

    ToCharacter(subject:, event:) ->
      process.send(
        subject,
        event.RoomSent(event.RoomToCharacter(event), room.id),
      )

    ToCharacterId(id:, event:) -> {
      case character_registry.whereis(system_tables.character, id) {
        Ok(subject) ->
          process.send(
            subject,
            event.RoomSent(event.RoomToCharacter(event), room.id),
          )

        _ -> Nil
      }
    }

    ToZone(id:, event:) ->
      case zone_registry.whereis(system_tables.zone, id) {
        Ok(subject) -> process.send(subject, event.RoomToZone(event))
        _ -> Nil
      }

    ToRoom(id:, event:) ->
      case room_registry.whereis(system_tables.room, id) {
        Ok(subject) -> process.send(subject, event.RoomToRoom(event))
        _ -> Nil
      }

    // Sends a room message to all subscribers of the room channel.
    //
    Broadcast(channel:, event:) ->
      communication.publish(
        system_tables.communication,
        channel,
        event.RoomSent(event.RoomToCharacter(event), room.id),
      )

    // Warning! Blocks until the table is up-to-date to keep the table in sync
    // for broadcasts.
    Subscribe(channel:, subscriber:) -> {
      let _ =
        communication.subscribe(
          system_tables.communication,
          channel,
          subscriber,
        )
      Nil
    }

    // Warning! Blocks until the table is up-to-date to keep the table in sync
    // for broadcasts.
    Unsubscribe(channel:, subscriber:) -> {
      let _ =
        communication.unsubscribe(
          system_tables.communication,
          channel,
          subscriber,
        )
      Nil
    }
  }
}
