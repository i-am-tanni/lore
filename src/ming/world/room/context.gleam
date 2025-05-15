//// A module for building responses to room events received by rooms.
//// 

import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/function
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import ming/character
import ming/character/view.{type View}
import ming/server/output
import ming/world.{
  type CharacterEvent, type CharacterMessage, type Event, type Mobile, type Room,
  type RoomEvent, type RoomExit, type RoomMessage, type Zone, Room, ToController,
}
import ming/world/channel.{type Channel, RoomChannel}
import ming/world/id.{type Id}
import ming/world/item.{type ItemInstance}
import ming/world/room/room_registry
import ming/world/zone

/// A builder for a response to a room event that wraps the room context.
/// 
pub opaque type Context(a) {
  Context(
    data: world.Room,
    output: List(#(Subject(CharacterMessage), output.Text)),
    events: List(EventToSend(a)),
    update_characters: Option(List(Mobile)),
    update_items: Option(List(ItemInstance)),
  )
}

/// A completed response to an event received by the room.
/// 
pub opaque type Response(a) {
  Response(
    events: List(EventToSend(a)),
    output: List(#(Subject(CharacterMessage), output.Text)),
    update_characters: Option(List(Mobile)),
    update_items: Option(List(ItemInstance)),
  )
}

/// Events are queued and processed after the response is fully built.
/// Events are tagged by recipient.
/// 
pub type EventToSend(a) {
  /// Reply to the author of an event asychronously.
  /// 
  ReplyAsync(reply_to: Subject(a), event: a)
  /// Send an event to an individiual character.
  /// 
  ToCharacter(id: Id(Mobile), event: Event(CharacterEvent, RoomMessage))
  /// Broadcast an event to all subscribers in the room channel
  /// 
  Broadcast(channel: Channel, event: Event(CharacterEvent, RoomMessage))
  /// Send an event from room to room
  /// 
  ToRoom(id: Id(world.Room), event: Event(RoomEvent, RoomMessage))
  /// Send an event to the zone.
  /// 
  ToZone(id: Id(Zone), event: Event(world.ZoneEvent, RoomMessage))
}

/// The room creates the response builder to be handed off to the event handler.
/// 
pub fn new(room: world.Room) -> Context(a) {
  Context(
    data: room,
    output: [],
    events: [],
    update_characters: None,
    update_items: None,
  )
}

/// Exposes the room data.
/// 
pub fn data(context: Context(a)) -> world.Room {
  context.data
}

/// 
pub fn self() -> process.Subject(world.RoomMessage) {
  process.new_subject()
}

/// Finds a local exit based on the given boolean function.
/// 
pub fn find_local_exit(
  context: Context(a),
  matcher: fn(RoomExit) -> Bool,
) -> Result(RoomExit, Nil) {
  list.find(context.data.exits, matcher)
}

/// Finds a local character based on the given boolean function.
/// 
pub fn find_local_character(
  context: Context(a),
  matcher: fn(Mobile) -> Bool,
) -> Result(Mobile, Nil) {
  list.find(context.data.characters, matcher)
}

/// Queue an event to the queue to be fired off in order when response is
/// completed.
/// 
pub fn event(context: Context(a), event: EventToSend(a)) -> Context(a) {
  Context(..context, events: [event, ..context.events])
}

/// Convert the response builder to a response to be processed by the room.
/// 
pub fn to_response(context: Context(a)) -> Response(a) {
  Response(
    events: list.reverse(context.events),
    // we don't reverse the output list because we're going to reverse it later
    output: context.output,
    update_characters: context.update_characters,
    update_items: context.update_items,
  )
}

/// Queue a CharacterEvent to be broadcasted to all subscribers of the room
/// channel. This is useful for witnessed events.
/// 
pub fn broadcast(
  context: Context(a),
  event: Event(CharacterEvent, RoomMessage),
) -> Context(a) {
  let queued_event = Broadcast(RoomChannel(context.data.id), event)
  Context(..context, events: [queued_event, ..context.events])
}

/// Queue a room-side text render to a Character subject.
/// 
pub fn render(
  context: Context(a),
  subject: Subject(CharacterMessage),
  view: View,
) -> Context(a) {
  let output = output.Text(text: view.to_string_tree(view), newline: False)
  Context(..context, output: [#(subject, output), ..context.output])
}

/// Queue a room-side text render to a character but with a newline.
/// 
pub fn renderln(
  context: Context(a),
  subject: Subject(CharacterMessage),
  view: View,
) -> Context(a) {
  let output = output.Text(text: view.to_string_tree(view), newline: True)
  Context(..context, output: [#(subject, output), ..context.output])
}

/// Insert a character into the room. 
/// 
pub fn character_insert(
  context: Context(a),
  character: world.Mobile,
) -> Context(a) {
  let Room(characters:, ..) = context.data
  Context(..context, update_characters: Some([character, ..characters]))
}

/// Delete a character from the room.
/// 
pub fn character_delete(
  context: Context(a),
  character: world.Mobile,
) -> Context(a) {
  let Room(characters:, ..) = context.data
  let mobile_id = character.id
  let filtered = list.filter(characters, fn(mobile) { mobile.id != mobile_id })
  Context(..context, update_characters: Some(filtered))
}

/// Insert an item into the room.
/// 
pub fn item_insert(context: Context(a), item: ItemInstance) -> Context(a) {
  let Room(items:, ..) = context.data
  Context(..context, update_items: Some([item, ..items]))
}

/// Delete an item from the room.
/// 
pub fn item_delete(context: Context(a), item: ItemInstance) -> Context(a) {
  let Room(items:, ..) = context.data
  let instance_id = item.id
  let filtered = list.filter(items, fn(item) { item.id != instance_id })
  Context(..context, update_items: Some(filtered))
}

/// Process a response to a RoomEvent and commit staged state changes.
/// 
pub fn handle_response(room: world.Room, response: Response(a)) -> world.Room {
  // group outputs by subject and then send each subject their output lists
  send_output(response.output)

  // fire off events
  list.each(response.events, send_event)

  // update room state
  let Response(update_characters:, update_items:, ..) = response
  case update_characters, update_items {
    Some(characters_update), Some(items_update) ->
      Room(..room, characters: characters_update, items: items_update)

    Some(characters_update), None -> Room(..room, characters: characters_update)

    None, Some(items_update) -> Room(..room, items: items_update)

    // no update
    None, None -> room
  }
}

fn send_output(output: List(#(Subject(CharacterMessage), output.Text))) -> Nil {
  case output {
    // if the list is empty, do nothing
    //
    [] -> Nil
    // ...otherwise if the list only has one message to send, send that
    //
    [#(subject, output)] -> actor.send(subject, world.RoomSentText([output]))
    // ...and if the list has more than one member, group by subject, reverse
    // the order, and send as a batch
    //
    _ ->
      group_by(output, function.identity)
      |> dict.to_list()
      |> list.each(fn(to_send) {
        let #(subject, output_list) = to_send
        actor.send(subject, world.RoomSentText(output_list))
      })
  }
}

fn send_event(event: EventToSend(a)) -> Nil {
  case event {
    ReplyAsync(reply_to:, event:) -> actor.send(reply_to, event)

    ToCharacter(id:, event:) ->
      case character.whereis(id) {
        Ok(subject) ->
          actor.send(subject, ToController(world.RoomSentEvent(event)))

        Error(Nil) -> Nil
      }

    ToZone(id:, event:) ->
      case zone.whereis(id) {
        Ok(subject) -> actor.send(subject, event)
        Error(Nil) -> Nil
      }

    Broadcast(channel:, event:) ->
      channel.publish(channel, ToController(world.RoomSentEvent(event)))

    ToRoom(id:, event:) ->
      case room_registry.whereis(id) {
        Ok(subject) -> actor.send(subject, world.RoomToRoom(event))
        Error(Nil) -> Nil
      }
  }
}

// Groups items in the list, but unlike list.group, the values are mapped.
// Note that in this case, the value list for each key will be reversed, which 
// is desirable in this specific circumstance for this module's use.
// 
fn group_by(list: List(a), group_fun: fn(a) -> #(k, v)) -> Dict(k, List(v)) {
  list.fold(list, dict.new(), fn(acc, x) {
    let #(key, val) = group_fun(x)
    case dict.get(acc, key) {
      Ok(list) -> dict.insert(acc, key, [val, ..list])
      Error(Nil) -> dict.insert(acc, key, [val])
    }
  })
}
