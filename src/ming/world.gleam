import gleam/erlang/process.{type Subject}
import gleam/option.{type Option}
import ming/server/output
import ming/world/id.{type Id}
import ming/world/item.{type ItemInstance}

pub type RoomTemplate

pub type Zone {
  Zone(rooms: List(Room))
}

pub type Room {
  Room(
    id: Id(Room),
    template_id: Id(RoomTemplate),
    zone_id: Id(Zone),
    zone_subject: Subject(ZoneEvent),
    name: String,
    exits: List(RoomExit),
    characters: List(Mobile),
    items: List(ItemInstance),
  )
}

pub type Direction {
  North
  South
  East
  West
  Up
  Down
  Custom(String)
}

pub type RoomExit {
  RoomExit(
    id: Id(RoomExit),
    keyword: Direction,
    from_room_id: Id(Room),
    to_room_id: Id(Room),
  )
}

pub type Private {
  Trimmed
  PlayerData
  NpcData
}

/// A vote by a room whether to accept or reject the move
pub type Vote(a) {
  Approve
  Reject(reason: a)
}

/// A mobile instance that is generated from a template or is a player.
/// The short field is the short description that shows in the room.
/// 
pub type Mobile {
  Mobile(
    id: Id(Mobile),
    room_id: Id(Room),
    template: MobTemplate,
    name: String,
    keywords: List(String),
    short: String,
    private: Private,
  )
}

/// Npc's have a template number that ties back to the database whereas players
/// will not.
/// 
pub type MobTemplate {
  Npc(id.Id(MobTemplate))
  Player
}

/// This type is the primary means by which units of concurrency (Mobiles,
/// Rooms, Zones, etc.) communicate. The event represents the incoming 
/// event and response represents the type the sender is expecting to receive
/// back.
///
pub type Event(a, b) {
  Event(data: a, from: Subject(b), initiated_by: EventAuthor)
}

/// The author of the event
///
pub type EventAuthor {
  ActingCharacter(Mobile)
  World
}

/// An internal event that a character can receive
/// 
pub type CharacterEvent {
  MoveNotifyArrive(from_exit: Option(RoomExit), character: Mobile)
  MoveNotifyDepart(to_exit: Option(RoomExit), character: Mobile)
}

// Events handled by rooms
/// 
pub type RoomEvent {
  /// A move request is received by the room from the requester.
  /// 
  MoveRequest(exit_keyword: Direction)
  /// The zone polls the desination room whether it accepts or rejects the move.
  /// 
  MovePoll(character: Mobile)
  /// If the move is approved, a depart event is sent by the Zone via a call.
  MoveDepart(character: Mobile, exit_keyword: Direction)
  ///...and an arrive event is sent by the zone right after the depart event
  /// to sync the move.
  /// 
  MoveArrive(
    character: Mobile,
    from_room_id: Id(Room),
    subject: Subject(CharacterMessage),
  )
  /// A signal to sent the acting character information about the room.
  /// 
  Look
}

/// Zones are a sync point for inter-room events like movement and doors.
/// 
pub type ZoneEvent {
  /// Polls the destination room and syncs the move commit upon approval
  /// 
  MoveKickoff(
    subject: Subject(CharacterMessage),
    character: Mobile,
    from_room_id: Id(Room),
    to_room_id: Id(Room),
    from_room_subject: Subject(RoomMessage),
    to_room_subject: Subject(RoomMessage),
    exit_keyword: Direction,
  )

  MoveVote(vote: Vote(MoveError))
  MoveProceed
}

/// This is a request that is received by the character process
/// to be turned into a response via a Conn builder.
/// 
pub type CharacterMessage {
  /// Text output that was received from the room to be sent to the user.
  /// 
  RoomSentText(text: List(output.Text))

  /// A character message to be passed to the character's controller for
  /// handling.
  /// 
  ToController(ControllerMessage)
}

pub type ControllerMessage {
  /// A command was received over the wire.
  /// 
  UserSentCommand(text: String)

  /// An event request was received from the room to be processed.
  /// 
  RoomSentEvent(event: Event(CharacterEvent, RoomMessage))
}

/// The wrapper type for messages that can be received by a Room.
/// 
pub type RoomMessage {
  UserToRoom(event: Event(RoomEvent, CharacterMessage))
  ZoneToRoom(event: Event(RoomEvent, ZoneMessage))
  RoomToRoom(event: Event(RoomEvent, RoomMessage))
}

/// A wrapper type for messages that can be received by a Zone.
/// 
pub type ZoneMessage =
  Event(ZoneEvent, RoomMessage)

/// An error type defining all the ways a move from one room to another can fail
/// 
pub type MoveError {
  Unknown(exit: UnknownError)
  CharacterLacksPermission
  RoomSetToPrivate
  ExitBlocked(direction: Direction)
  RoomLookupFailed(room_id: Id(Room))
  CallFailed(reason: process.CallError(ZoneMessage))
  ArrivalFailed(reason: process.CallError(ZoneMessage))
}

/// An error type for describing no match was found.
/// 
pub type UnknownError {
  UnknownExit(direction: Direction)
}
