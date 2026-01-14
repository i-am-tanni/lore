//// A zone processes a mobile's move from one room to another.
////
//// ## Steps to complete a move:
//// 1. Poll the receiving room whether it accepts or rejects the move.
//// 2. If the receiving room accepts, notify the character to update their
//// room_id location.
//// 3. Update the character's location in the presence table
//// 4. Send a `MoveDepart` event to the departure room and block until response.
//// 5. Finally, send a `MoveArrive` event to the arrival room.
////

import gleam/erlang/process.{type Subject}
import gleam/option.{Some}
import gleam/result
import lore/world.{type ErrorRoomRequest, RoomLookupFailed}
import lore/world/event.{
  type Event, type RoomMessage, type ZoneEvent, Done, MoveKickoffData, MovePoll,
}
import lore/world/room/room_registry
import lore/world/system_tables

type Approved {
  Approved
}

/// Polls the destination room whether it accepts or rejects the move and if
/// approved, syncs the commit to both rooms.
///
pub fn call(
  system_tables: system_tables.Lookup,
  event: Event(ZoneEvent, RoomMessage),
  data: event.MoveKickoffData,
) -> Nil {
  let result = {
    let MoveKickoffData(to_room_id:, from: subject, ..) = data
    // Ask arrival if move is OK to proceed and block until answer is received
    let lookup =
      room_registry.whereis(system_tables.room, to_room_id)
      |> result.replace_error(RoomLookupFailed(to_room_id))

    use to_room_subject <- result.try(lookup)
    use Approved <- result.try(poll(to_room_subject, data))
    // ..if approved, notify the character to update their room id
    process.send(subject, commit(event.from, data))
    // and then block until departure is completed so we can start the arrival.
    let Done = process.call(event.from, 1000, depart(_, data))
    Ok(process.send(to_room_subject, arrive(data.from, data)))
  }

  case result {
    Ok(_) -> Nil
    Error(reason) -> process.send(data.from, abort(event.from, reason, data))
  }
}

// RoomMessage constructor for MovePoll.
// This will poll the receiving room if it accepts the move.
fn poll(
  subject: Subject(RoomMessage),
  data: event.MoveKickoffData,
) -> Result(Approved, ErrorRoomRequest) {
  let acting_character = data.acting_character
  let data = MovePoll(acting_character)
  let constructor = fn(caller) {
    event.new(from: caller, acting_character:, data:)
    |> event.PollRoom()
  }

  case process.call(subject, 1000, constructor) {
    world.Approve -> Ok(Approved)
    world.Reject(reason) -> Error(reason)
  }
}

fn commit(
  from_room_subject: Subject(RoomMessage),
  data: event.MoveKickoffData,
) -> event.CharacterMessage {
  let event.MoveKickoffData(from_room_id:, to_room_id:, acting_character:, ..) =
    data

  event.new(
    from_room_subject,
    acting_character:,
    data: event.MoveCommit(to_room_id),
  )
  |> event.RoomToCharacter
  |> event.RoomSent(from: from_room_id)
}

fn abort(
  from_room_subject: Subject(RoomMessage),
  reason: world.ErrorRoomRequest,
  data: event.MoveKickoffData,
) -> event.CharacterMessage {
  let event.MoveKickoffData(from_room_id:, acting_character:, ..) = data
  let data = event.ActFailed(reason)

  event.new(from: from_room_subject, acting_character:, data:)
  |> event.RoomToCharacter
  |> event.RoomSent(from: from_room_id)
}

fn depart(self: Subject(event.Done), data: event.MoveKickoffData) -> RoomMessage {
  let event.MoveKickoffData(acting_character:, exit_keyword:, ..) = data
  let data =
    event.MoveDepartData(exit_keyword: exit_keyword, subject: data.from)
    |> event.MoveDepart

  event.new(from: self, acting_character:, data:)
  |> event.InterRoom
}

// Note we "fake" that this event is generated and sent from the
// acting_character so that the room will reply to them.
//
fn arrive(
  character_subject: Subject(event.CharacterMessage),
  data: event.MoveKickoffData,
) -> RoomMessage {
  let event.MoveKickoffData(acting_character:, from_room_id:, exit_keyword:, ..) =
    data
  let data =
    event.MoveArriveData(
      from_room_id: Some(from_room_id),
      from_exit_keyword: exit_keyword,
    )
    |> event.MoveArrive

  event.new(from: character_subject, acting_character:, data:)
  |> event.CharacterToRoom
}
