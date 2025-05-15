//// A zone processes a mobile's move from one room to another.
//// 
//// ## Steps to complete a move:
//// 1. Poll the receiving room whether it accepts or rejects the move.
//// 2. If the receiving room accepts, send a MoveDepart event to the departure
//// room.
//// 3. Then send a MoveArrive event to the arrival room.
//// 4. Finally, update the presence cache that tracks player location.

import gleam/bool
import gleam/erlang/process.{type Subject}
import gleam/result
import ming/world.{
  type Event, type MoveError, type RoomMessage, type ZoneEvent, type ZoneMessage,
  ArrivalFailed, CallFailed, Event, MoveArrive, MoveDepart, MoveKickoff,
  MovePoll, MoveVote, Player, ZoneToRoom,
}
import ming/world/room/presence
import ming/world/zone/context.{type Context}

type Approved {
  Approved
}

/// Polls the destination room whether it accepts or rejects the move and if
/// approved, syncs the commit to both rooms via calls.
///
pub fn process(
  context: Context,
  event: Event(ZoneEvent, RoomMessage),
) -> Result(Nil, world.MoveError) {
  let data = event.data
  let assert world.MoveKickoff(
    character:,
    from_room_subject:,
    to_room_subject:,
    to_room_id:,
    ..,
  ) = data
  // Seek approval from receiving room
  use vote_event <- result.try(call(to_room_subject, poll(_, data), CallFailed))
  use Approved <- result.try(vote_to_result(vote_event))
  // Complete move transaction synchronously
  use _ <- result.try(call(from_room_subject, depart(_, data), CallFailed))
  use _ <- result.try(call(to_room_subject, arrive(_, data), ArrivalFailed))
  // ...then record the move in the presence table if character is player
  use <- bool.guard(character.template != Player, Ok(Nil))
  Ok(presence.insert(context.presence, character.id, to_room_id))
}

// Wrapper around process.try_call that maps the error.
fn call(
  subject: Subject(RoomMessage),
  msg_fun: fn(Subject(ZoneMessage)) -> RoomMessage,
  error_wrapper: fn(process.CallError(ZoneMessage)) -> MoveError,
) -> Result(ZoneMessage, MoveError) {
  process.try_call(subject, msg_fun, 2000)
  |> result.map_error(error_wrapper)
}

// RoomMessage constructor for MovePoll.
// This will poll the receiving room if it accepts the move.
fn poll(
  caller: Subject(ZoneMessage),
  event: world.ZoneEvent,
) -> world.RoomMessage {
  let assert MoveKickoff(character:, ..) = event
  Event(initiated_by: world.World, from: caller, data: MovePoll(character))
  |> ZoneToRoom()
}

// RoomMessage constructor for MoveDepart.
// This event will remove the character from the departure room.
fn depart(caller: Subject(ZoneMessage), event: ZoneEvent) -> world.RoomMessage {
  let assert MoveKickoff(character:, exit_keyword:, ..) = event

  Event(
    initiated_by: world.World,
    from: caller,
    data: MoveDepart(character: character, exit_keyword: exit_keyword),
  )
  |> ZoneToRoom()
}

// RoomMessage constructor for MoveArrive.
// This event will add the character to the arrival room.
fn arrive(caller: Subject(ZoneMessage), event: ZoneEvent) -> world.RoomMessage {
  let assert MoveKickoff(character:, from_room_id:, subject:, ..) = event

  Event(
    initiated_by: world.World,
    from: caller,
    data: MoveArrive(
      character: character,
      from_room_id: from_room_id,
      subject: subject,
    ),
  )
  |> ZoneToRoom()
}

// Converts a vote event to a result.
fn vote_to_result(
  event: Event(ZoneEvent, RoomMessage),
) -> Result(Approved, MoveError) {
  let assert world.MoveVote(vote: vote) = event.data
  case vote {
    world.Approve -> Ok(Approved)
    world.Reject(error) -> Error(error)
  }
}
