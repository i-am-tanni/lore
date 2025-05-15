import gleam/erlang/process.{type Subject}
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/result
import ming/character/view/error_view
import ming/character/view/move_view
import ming/world.{
  type CharacterMessage, type Direction, type Event, type MoveError, type Room,
  type RoomEvent, type RoomExit, type RoomMessage, type ZoneEvent,
  ActingCharacter, Approve, Event, MoveArrive, MoveDepart, MoveNotifyArrive,
  MoveNotifyDepart, MoveVote, Room, RoomExit, RoomLookupFailed, Unknown,
  UnknownExit,
}
import ming/world/channel
import ming/world/id.{type Id}
import ming/world/room/context.{type Context}
import ming/world/room/room_registry

pub fn request(
  context: Context(CharacterMessage),
  event: Event(RoomEvent, CharacterMessage),
) -> Context(CharacterMessage) {
  case vote_kickoff(context, event) {
    Ok(move_kickoff) -> {
      let Room(zone_id:, ..) = context.data(context)
      context.event(context, context.ToZone(zone_id, move_kickoff))
    }
    Error(error) ->
      context.renderln(context, event.from, error_view.move_error(error))
  }
}

fn vote_kickoff(
  context: Context(a),
  event: Event(RoomEvent, CharacterMessage),
) -> Result(Event(ZoneEvent, world.RoomMessage), MoveError) {
  let assert Event(
    initiated_by: ActingCharacter(character),
    data: world.MoveRequest(exit_keyword:),
    ..,
  ) = event

  use exit_match <- result.try(find_local_exit(context, exit_keyword))
  let RoomExit(to_room_id:, ..) = exit_match
  use to_room_subject <- result.try(room_lookup(to_room_id))
  let self = context.self()
  let data =
    world.MoveKickoff(
      subject: event.from,
      character: character,
      from_room_id: exit_match.from_room_id,
      to_room_id: exit_match.to_room_id,
      from_room_subject: self,
      to_room_subject: to_room_subject,
      exit_keyword: exit_keyword,
    )

  Ok(Event(..event, from: self, data: data))
}

/// Destination room votes whether to accept the character's move.
/// 
pub fn vote_proceed(
  context: Context(ZoneEvent),
  event: Event(RoomEvent, world.ZoneMessage),
) -> Context(ZoneEvent) {
  let reply = Event(..event, data: MoveVote(Approve), from: context.self())
  actor.send(event.from, reply)
  context
}

/// Remove departing character from room and notify occupants
/// 
pub fn depart(
  context: Context(ZoneEvent),
  event: Event(RoomEvent, world.ZoneMessage),
) {
  let assert Event(data: MoveDepart(character:, exit_keyword:), ..) = event
  let room_exit =
    context.find_local_exit(context, exit_keyword_matches(_, exit_keyword))
    |> to_option

  let notification =
    Event(
      data: MoveNotifyDepart(to_exit: room_exit, character: character),
      initiated_by: ActingCharacter(character),
      from: context.self(),
    )

  context
  |> context.character_delete(character)
  |> context.broadcast(notification)
}

/// Add the arriving character to room and notify occupants.
/// 
pub fn arrive(
  context: Context(ZoneEvent),
  event: Event(RoomEvent, world.ZoneMessage),
) {
  let assert MoveArrive(character:, from_room_id:, subject:) = event.data

  let room_exit =
    context.find_local_exit(context, from_room_id_matches(_, from_room_id))
    |> to_option

  let notification =
    Event(
      data: MoveNotifyArrive(from_exit: room_exit, character: character),
      initiated_by: ActingCharacter(character),
      from: context.self(),
    )

  context
  |> context.broadcast(notification)
  |> context.character_insert(character)
  |> context.renderln(subject, move_view.exit(room_exit))
}

fn to_option(result: Result(a, Nil)) -> Option(a) {
  case result {
    Ok(x) -> Some(x)
    Error(Nil) -> None
  }
}

fn find_local_exit(
  context: Context(a),
  exit_keyword: Direction,
) -> Result(RoomExit, MoveError) {
  context.find_local_exit(context, exit_keyword_matches(_, exit_keyword))
  |> result.replace_error(Unknown(UnknownExit(exit_keyword)))
}

fn exit_keyword_matches(room_exit: RoomExit, direction: Direction) -> Bool {
  room_exit.keyword == direction
}

fn from_room_id_matches(room_exit: RoomExit, room_id: Id(Room)) -> Bool {
  room_exit.from_room_id == room_id
}

fn room_lookup(room_id: Id(Room)) -> Result(Subject(RoomMessage), MoveError) {
  room_registry.whereis(room_id)
  |> result.replace_error(RoomLookupFailed(room_id))
}
