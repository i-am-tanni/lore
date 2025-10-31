//// Events are the primary means by which messages are passed between
//// characters, rooms, zones, which are running concurrently to one another.
////
//// Message == a Wrapper for types a process can receive
//// - CharacterMessage
//// - RoomMessage
//// - ZoneMessage
////
//// Event is an Event type

import gleam/erlang/process.{type Subject}
import gleam/option.{type Option}
import gleam/order
import lore/character/view
import lore/server/output
import lore/world.{
  type Direction, type Id, type Mobile, type Room, type StringId,
}

/// This type is the primary means by which units of concurrency (Mobiles,
/// Rooms, Zones, etc.) communicate. The event represents the incoming
/// event and response represents the type the sender is expecting to receive
/// back.
///
pub type Event(a, b) {
  Event(data: a, from: Subject(b), acting_character: Mobile)
}

pub type Priority {
  Lag
  High
  Medium
  Low
}

pub fn is_priority_gt(a: Priority, b: Priority) -> Bool {
  compare_priority(a, b) == order.Gt
}

fn compare_priority(a: Priority, with b: Priority) -> order.Order {
  case a == b {
    True -> order.Eq
    False ->
      case a == Lag || priority_to_int(a) > priority_to_int(b) {
        True -> order.Gt
        False -> order.Lt
      }
  }
}

fn priority_to_int(priority: Priority) -> Int {
  case priority {
    Lag -> 4
    High -> 3
    Medium -> 2
    Low -> 1
  }
}

/// A lazy CharacterToRoomEvent that consumes time to perform.
/// Condition is required to pass in order to perform. Examples:
/// - For crafts, does the character have the requisite components?
/// - Is the character in the right position to perform the action?
///
pub type Action {
  /// Priority determines cancellability of the current action.
  /// Delay determines the cooldown time in ms after the action is performed.
  ///
  Action(
    id: StringId(Action),
    condition: fn(world.MobileInternal) -> Result(world.MobileInternal, String),
    priority: Priority,
    delay: Int,
    event: CharacterToRoomEvent,
  )
}

/// A type that returns the completion status of an event sent via
/// `process.call`.
///
pub type Done {
  Done
}

pub type NoReply

/// A type provided to the mob factory to spawn a mobile
///
pub type SpawnMobile {
  /// The endpoint is the (optional) connection controlling the character
  ///
  SpawnMobile(
    endpoint: Option(process.Subject(Outgoing)),
    mobile: world.MobileInternal,
  )
}

/// Outgoing messages from the character to a connection.
///
pub type Outgoing {
  /// A text transmission to be pushed to the socket.
  PushText(List(output.Text))
  /// A signal that communicates connection should be terminated.
  Halt(process.Pid)
  /// Reassigns connection to a new character.
  Reassign(subject: Subject(CharacterMessage))
}

/// This is a request that is received by the character process
/// to be turned into a response via a Conn builder.
///
pub type CharacterMessage {
  /// Text input is received from a connection
  ///
  UserSentCommand(text: String)
  /// A message received form a room will be checked to confirm that the
  /// character is in the room the event was received from, otherwise it will
  /// be automatically discarded.
  ///
  RoomSent(received: FromRoom, from: Id(Room))
  /// A timed signal sent by the character themself to trigger the next action
  /// in the queue.
  ///
  CooldownExpired(id: StringId(Action))
  /// A notification was received
  ///
  Chat(ChatData)
  /// Server wants the character to despawn or otherwise halt
  ///
  ServerRequestedShutdown
}

pub type FromRoom {
  RoomSentText(text: List(output.Text))
  RoomToCharacter(event: Event(CharacterEvent, RoomMessage))
}

/// The wrapper type for messages that can be received by a Room.
///
pub type RoomMessage {
  CharacterToRoom(event: Event(CharacterToRoomEvent, CharacterMessage))
  RoomToRoom(event: Event(RoomToRoomEvent, RoomMessage))
  PollRoom(event: Event(PollEvent, world.Vote(world.ErrorRoomRequest)))
  InterRoom(event: Event(InterRoomEvent, Done))
  MobileCleanup(id: StringId(Mobile))
  SpawnItem(item: world.ItemInstance)
}

/// A wrapper type for messages that can be received by a Zone.
///
pub type ZoneMessage {
  RoomToZone(event: Event(ZoneEvent, RoomMessage))
}

/// An event that a character can receive
///
pub type CharacterEvent {
  MoveNotifyArrive(NotifyArriveData)
  MoveNotifyDepart(NotifyDepartData)
  MoveCommit(to: Id(Room))
  DoorNotify(DoorNotifyData)
  Communication(CommunicationData)
  ItemGetNotify(item: world.ItemInstance)
  ItemDropNotify(item: world.ItemInstance)
  ItemInspect(item: world.ItemInstance)
  MobileInspectRequest(by: Subject(CharacterMessage))
  MobileInspectResponse(character: world.MobileInternal)
  CombatCommit(CombatCommitData)
  CombatRound(
    participants: List(world.Mobile),
    commits: List(world.CombatPollData),
  )
  ActFailed(world.ErrorRoomRequest)
}

pub type CharacterToRoomEvent {
  Look
  LookAt(keyword: String)
  MoveRequest(exit_keyword: Direction)
  MoveArrive(MoveArriveData)
  ItemGet(keyword: String)
  ItemDrop(item_instance: world.ItemInstance)
  RejoinRoom
  DoorToggle(DoorToggleData)
  DoorUpdateEnd(DoorUpdateData)
  RoomCommunication(RoomCommunicationData)
  CombatRequest(CombatRequestData)
}

/// The zone polls the desination room whether it accepts or rejects the move.
///
pub type PollEvent {
  MovePoll(character: Mobile)
}

/// An event that occurs synchronously between rooms via a call from the zone.
///
pub type InterRoomEvent {
  MoveDepart(MoveDepartData)
  DoorUpdateBegin(DoorUpdateData)
}

pub type RoomToRoomEvent {
  RoomToRoomEvent
}

// Room Event data

pub type MoveDepartData {
  MoveDepartData(
    exit_keyword: Option(Direction),
    subject: Subject(CharacterMessage),
  )
}

pub type MoveArriveData {
  MoveArriveData(
    from_room_id: Option(Id(Room)),
    from_exit_keyword: Option(world.Direction),
  )
}

pub type DoorToggleData {
  DoorToggleData(exit_keyword: Direction, desired_state: world.AccessState)
}

pub type DoorUpdateData {
  DoorUpdateData(
    door_id: Id(world.Door),
    update: world.AccessState,
    from_room_id: Id(Room),
  )
}

pub type RoomCommunicationData {
  SayData(text: String, adverb: Option(String))
  SayAtData(text: String, at: String, adverb: Option(String))
  WhisperData(text: String, at: String, adverb: Option(String))
  EmoteData(text: String)
  SocialData(report: view.Report)
  SocialAtData(report: view.Report, at: String)
}

// Character Data

pub type NotifyArriveData {
  NotifyArriveData(enter_keyword: Option(Direction), acting_character: Mobile)
}

pub type NotifyDepartData {
  NotifyDepartData(exit_keyword: Option(Direction), acting_character: Mobile)
}

pub type DoorNotifyData {
  DoorNotifyData(
    exit: world.RoomExit,
    update: world.AccessState,
    is_subject_observable: Bool,
  )
}

pub type CommunicationData {
  Say(text: String, adverb: Option(String))
  SayAt(text: String, adverb: Option(String), at: world.Mobile)
  Whisper(text: String, at: world.Mobile)
  Emote(text: String)
  Social(report: view.Report)
  SocialAt(report: view.Report, at: world.Mobile)
}

pub type ChatData {
  ChatData(channel: world.ChatChannel, username: String, text: String)
}

pub type CombatCommitData {
  CombatCommitData(attacker: world.Mobile, victim: world.Mobile, damage: Int)
}

/// Zones are a sync point for inter-room events like movement and doors.
///
pub type ZoneEvent {
  /// Polls the destination room and syncs the move commit upon approval
  ///
  MoveKickoff(MoveKickoffData)
  DoorSync(DoorSyncData)
}

pub type MoveKickoffData {
  MoveKickoffData(
    from: Subject(CharacterMessage),
    acting_character: Mobile,
    from_room_id: Id(Room),
    to_room_id: Id(Room),
    exit_keyword: Direction,
  )
}

/// Data sent to the zone for the purpose of syncing matching door sides in two
/// different rooms together.
///
pub type DoorSyncData {
  DoorSyncData(
    from: Subject(CharacterMessage),
    from_room_id: Id(Room),
    door_id: Id(world.Door),
    to_room_id: Id(Room),
    update: world.AccessState,
  )
}

pub type SearchTerm(a) {
  Keyword(String)
  SearchId(StringId(a))
}

pub type CombatRequestData {
  CombatRequestData(
    victim: SearchTerm(Mobile),
    dam_roll: Int,
    is_round_based: Bool,
  )
}

pub fn new(
  from subject: Subject(b),
  acting_character acting_character: Mobile,
  data data: a,
) -> Event(a, b) {
  Event(from: subject, acting_character: acting_character, data: data)
}

pub fn is_from_acting_character(
  event: Event(a, b),
  character: world.MobileInternal,
) -> Bool {
  event.acting_character.id == character.id
}
