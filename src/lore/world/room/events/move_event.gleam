//// Room events relating to character insertion / deletion into a room
//// (e.g. movement).
////

import gleam/list
import gleam/option.{None, Some}
import gleam/result
import lore/character/view/move_view
import lore/world.{
  type Direction, type ErrorRoomRequest, type RoomExit, UnknownExit,
}
import lore/world/event.{
  type CharacterMessage, type CharacterToRoomEvent, type Event,
  type MoveArriveData, type MoveDepartData, MoveArriveData, MoveDepartData,
  MoveNotifyArrive, MoveNotifyDepart, NotifyArriveData, NotifyDepartData,
}
import lore/world/room/events/look_event
import lore/world/room/presence
import lore/world/room/response
import lore/world/system_tables

/// The initial movement request by a character for an exit keyword.
///
pub fn request(
  builder: response.Builder(CharacterMessage),
  event: Event(CharacterToRoomEvent, CharacterMessage),
  exit_keyword: world.Direction,
) -> response.Builder(CharacterMessage) {
  let result = {
    // If exit exists, kickoff, lookup room subject and send to zone
    // This cannot fail as only characters can initiate move events
    let acting_character = event.acting_character
    use exit_match <- result.try(find_local_exit(builder, exit_keyword))
    use _ <- result.try(check_access(exit_match))
    let world.RoomExit(from_room_id:, to_room_id:, ..) = exit_match
    let from = event.from
    let data =
      event.MoveKickoffData(
        from:,
        acting_character:,
        from_room_id:,
        to_room_id:,
        exit_keyword:,
      )
      |> event.MoveKickoff

    event.new(from: response.self(builder), acting_character:, data:)
    |> Ok
  }

  case result {
    Ok(move_kickoff) -> response.zone_event(builder, move_kickoff)
    Error(reason) ->
      response.reply_character(builder, event, event.ActFailed(reason))
  }
}

/// Destination room votes whether to accept the character's move.
///
pub fn vote(
  context: response.Builder(world.Vote(ErrorRoomRequest)),
  _event: Event(event.PollEvent, world.Vote(ErrorRoomRequest)),
  _data: world.Mobile,
) -> response.Builder(world.Vote(ErrorRoomRequest)) {
  response.reply(context, world.Approve)
}

/// Remove departing character from room and notify occupants.
///
pub fn depart(
  builder: response.Builder(event.Done),
  event: Event(event.InterRoomEvent, event.Done),
  data: MoveDepartData,
) -> response.Builder(event.Done) {
  let acting_character = event.acting_character

  let MoveDepartData(exit_keyword:, subject:) = data

  let data = NotifyDepartData(exit_keyword:, acting_character:)

  builder
  |> response.character_delete(acting_character)
  |> response.unsubscribe_character(subject)
  |> response.broadcast(acting_character, MoveNotifyDepart(data))
  |> response.reply(event.Done)
}

/// Add the arriving character to room and notify occupants.
///
pub fn arrive(
  builder: response.Builder(CharacterMessage),
  event: Event(event.CharacterToRoomEvent, CharacterMessage),
  data: MoveArriveData,
) -> response.Builder(CharacterMessage) {
  let acting_character = event.acting_character
  let MoveArriveData(from_room_id, from_exit_keyword) = data

  // Check to see if there is a direction we can infer from the arrival
  let room_exit = case from_room_id {
    Some(id) ->
      response.find_local_exit(builder, fn(room_exit) {
        room_exit.to_room_id == id
      })
      |> option.from_result

    None -> None
  }

  let enter_keyword = case room_exit {
    Some(world.RoomExit(keyword:, ..)) -> Some(keyword)
    None -> None
  }

  // We will send occupants an arrival notification
  let data = NotifyArriveData(enter_keyword:, acting_character:)

  // Update presence table
  let system_tables.Lookup(presence:, ..) = response.system_tables(builder)
  let world.Room(id: room_id, ..) = response.room(builder)
  presence.update(presence, event.from, event.acting_character.id, room_id)

  let builder =
    builder
    |> response.broadcast(acting_character, MoveNotifyArrive(data))
    |> response.character_insert(acting_character)
    |> response.subscribe_character(event.from)

  case is_player(event.acting_character) {
    True ->
      builder
      |> response.renderln(move_view.exit(from_exit_keyword))
      |> look_event.room_look(event)

    False -> builder
  }
}

/// Only called if character restarted and needs to resubscribe to the room.
///
pub fn rejoin(
  builder: response.Builder(CharacterMessage),
  event: Event(event.CharacterToRoomEvent, CharacterMessage),
) -> response.Builder(CharacterMessage) {
  // Check that requester is in the room they believe themselves to be in
  // before subscribing them
  let acting_character_id = event.acting_character.id
  let world.Room(characters:, ..) = response.room(builder)
  let is_present =
    list.any(characters, fn(mobile) { mobile.id == acting_character_id })

  case is_present {
    True -> response.subscribe_character(builder, event.from)
    // Well this is awkward...
    False -> builder
  }
}

// Confirm exit is accessible
fn check_access(exit: RoomExit) -> Result(Nil, ErrorRoomRequest) {
  case exit.door {
    Some(door) ->
      case door.state {
        world.Open -> Ok(Nil)
        world.Closed -> Error(world.DoorErr(world.DoorClosed))
      }

    None -> Ok(Nil)
  }
}

fn find_local_exit(
  builder: response.Builder(a),
  exit_keyword: Direction,
) -> Result(RoomExit, ErrorRoomRequest) {
  response.find_local_exit(builder, exit_keyword_matches(_, exit_keyword))
  |> result.replace_error(UnknownExit(exit_keyword))
}

fn exit_keyword_matches(room_exit: RoomExit, direction: Direction) -> Bool {
  room_exit.keyword == direction
}

fn is_player(mobile: world.Mobile) -> Bool {
  case mobile.template_id {
    world.Player(_) -> True
    world.Npc(_) -> False
  }
}
