import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/option.{Some}
import gleam/otp/actor
import gleam/result.{try}
import lore/world.{type Id, type SpawnGroup, type Zone}
import lore/world/event.{
  type Done, type Event, type RoomMessage, type ZoneEvent, type ZoneMessage,
  Done, MoveKickoffData, ResetSpawnGroup, RoomToZone,
}
import lore/world/room/room_registry
import lore/world/system_tables
import lore/world/zone/spawner
import lore/world/zone/zone_registry

pub type State {
  State(
    self: process.Subject(ZoneMessage),
    zone: Zone,
    system_tables: system_tables.Lookup,
    spawn_groups: Dict(Id(SpawnGroup), SpawnGroup),
  )
}

pub fn start(
  zone: Zone,
  system_tables: system_tables.Lookup,
) -> Result(actor.Started(Subject(ZoneMessage)), actor.StartError) {
  actor.new_with_initialiser(100, fn(self) { init(self, zone, system_tables) })
  |> actor.on_message(recv)
  |> actor.start
}

fn init(
  self: process.Subject(ZoneMessage),
  zone: Zone,
  system_tables: system_tables.Lookup,
) -> Result(actor.Initialised(State, ZoneMessage, Subject(ZoneMessage)), String) {
  // register zone on init

  zone_registry.register(system_tables.zone, zone.id, self)

  let spawn_groups =
    list.map(zone.spawn_groups, fn(group) {
      let group = spawner.reset_group(group, system_tables)
      let _ = schedule_next_reset(self, group)
      #(group.id, group)
    })
    |> dict.from_list

  State(self:, zone:, system_tables:, spawn_groups:)
  |> actor.initialised()
  |> actor.returning(self)
  |> Ok
}

fn recv(state: State, msg: ZoneMessage) -> actor.Next(State, ZoneMessage) {
  let state = case msg {
    RoomToZone(event) ->
      case event.data {
        event.MoveKickoff(data) -> {
          move_request(state.system_tables, event, data)
          state
        }
        event.DoorSync(data) -> {
          door_update(state.system_tables, event, data)
          state
        }
      }

    ResetSpawnGroup(group_id) -> reset_spawn_group(state, group_id)
  }

  actor.continue(state)
}

fn reset_spawn_group(state: State, group_id: Id(SpawnGroup)) -> State {
  let spawn_groups = state.spawn_groups
  let result = {
    use group <- try(dict.get(spawn_groups, group_id))
    let group = spawner.reset_group(group, state.system_tables)
    let _ = schedule_next_reset(state.self, group)

    Ok(dict.insert(spawn_groups, group_id, group))
  }

  case result {
    Ok(update) -> State(..state, spawn_groups: update)
    Error(_) -> state
  }
}

fn schedule_next_reset(
  self: process.Subject(ZoneMessage),
  group: SpawnGroup,
) -> Result(process.Timer, Nil) {
  case group.is_enabled {
    True ->
      Ok(process.send_after(
        self,
        group.reset_freq * 1000,
        ResetSpawnGroup(group.id),
      ))

    False -> Error(Nil)
  }
}

type Approved {
  Approved
}

/// Polls the destination room whether it accepts or rejects the move and if
/// approved, syncs the commit to both rooms.
///
pub fn move_request(
  system_tables: system_tables.Lookup,
  event: Event(ZoneEvent, RoomMessage),
  data: event.MoveKickoffData,
) -> Nil {
  let result = {
    let MoveKickoffData(to_room_id:, from: subject, ..) = data
    // Ask arrival if move is OK to proceed and block until answer is received
    let lookup =
      room_registry.whereis(system_tables.room, to_room_id)
      |> result.replace_error(world.RoomLookupFailed(to_room_id))

    use to_room_subject <- result.try(lookup)
    use Approved <- result.try(move_poll(to_room_subject, data))
    // ..if approved, notify the character to update their room id
    process.send(subject, move_commit(event.from, data))
    // and then block until departure is completed so we can start the arrival.
    let Done = process.call(event.from, 1000, move_depart(_, data))
    Ok(process.send(to_room_subject, move_arrive(data.from, data)))
  }

  case result {
    Ok(_) -> Nil
    Error(reason) ->
      process.send(data.from, move_abort(event.from, reason, data))
  }
}

// RoomMessage constructor for MovePoll.
// This will poll the receiving room if it accepts the move.
fn move_poll(
  subject: Subject(RoomMessage),
  data: event.MoveKickoffData,
) -> Result(Approved, world.ErrorRoomRequest) {
  let acting_character = data.acting_character
  let data = event.MovePoll(acting_character)
  let constructor = fn(caller) {
    event.new(from: caller, acting_character:, data:)
    |> event.PollRoom()
  }

  case process.call(subject, 1000, constructor) {
    world.Approve -> Ok(Approved)
    world.Reject(reason) -> Error(reason)
  }
}

fn move_commit(
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

fn move_abort(
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

fn move_depart(
  self: Subject(event.Done),
  data: event.MoveKickoffData,
) -> RoomMessage {
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
fn move_arrive(
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

pub fn door_update(
  system_tables: system_tables.Lookup,
  event: Event(ZoneEvent, RoomMessage),
  data: event.DoorSyncData,
) -> Nil {
  let event.DoorSyncData(door_id:, to_room_id:, from_room_id:, update:, from:) =
    data

  let result = {
    let lookup =
      room_registry.whereis(system_tables.room, to_room_id)
      |> result.replace_error(world.RoomLookupFailed(to_room_id))

    use to_room_subject <- result.try(lookup)
    let door_update_data =
      event.DoorUpdateData(door_id:, update:, from_room_id:)
    let Done =
      process.call(event.from, 1000, door_begin(_, event, door_update_data))
    Ok(process.send(to_room_subject, door_end(from, event, door_update_data)))
  }

  case result {
    Ok(_) -> Nil
    Error(reason) -> process.send(data.from, door_abort(event, reason, data))
  }
}

fn door_begin(
  self: process.Subject(Done),
  event: Event(ZoneEvent, RoomMessage),
  data: event.DoorUpdateData,
) -> RoomMessage {
  let acting_character = event.acting_character
  let data = event.DoorUpdateBegin(data)
  let event = event.new(from: self, acting_character: acting_character, data:)
  event.InterRoom(event)
}

fn door_end(
  from: process.Subject(event.CharacterMessage),
  event: Event(ZoneEvent, RoomMessage),
  data: event.DoorUpdateData,
) -> RoomMessage {
  let acting_character = event.acting_character
  let data = event.DoorUpdateEnd(data)
  let event = event.new(from:, acting_character:, data:)
  event.CharacterToRoom(event)
}

fn door_abort(
  event: Event(ZoneEvent, RoomMessage),
  reason: world.ErrorRoomRequest,
  data: event.DoorSyncData,
) -> event.CharacterMessage {
  let event.DoorSyncData(from_room_id:, ..) = data
  let event.Event(from:, acting_character:, ..) = event

  event.new(from:, acting_character:, data: event.ActFailed(reason))
  |> event.RoomToCharacter
  |> event.RoomSent(from: from_room_id)
}
