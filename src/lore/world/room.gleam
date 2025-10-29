/// An actor for a room process, which serves as a synchronization point
/// for physical actions and tracks the room state.
///
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/otp/actor
import lore/world.{type Room}
import lore/world/event.{type Event, type RoomMessage}
import lore/world/room/events/combat_event
import lore/world/room/events/comm_event
import lore/world/room/events/door_event
import lore/world/room/events/item_event
import lore/world/room/events/look_event
import lore/world/room/events/move_event
import lore/world/room/response
import lore/world/room/room_registry
import lore/world/system_tables

pub type State {
  State(
    room: world.Room,
    system_tables: system_tables.Lookup,
    self: process.Subject(RoomMessage),
  )
}

/// Starts a room and registers it.
///
pub fn start(
  room: Room,
  system_tables: system_tables.Lookup,
) -> Result(actor.Started(process.Subject(RoomMessage)), actor.StartError) {
  actor.new_with_initialiser(100, fn(self) { init(self, room, system_tables) })
  |> actor.on_message(recv)
  |> actor.start
}

fn init(
  self: process.Subject(RoomMessage),
  room: Room,
  system_tables: system_tables.Lookup,
) -> Result(actor.Initialised(State, RoomMessage, Subject(RoomMessage)), String) {
  // register room on init
  room_registry.register(system_tables.room, room.id, self)

  let update =
    list.map(room.items, fn(instance) {
      world.ItemInstance(..instance, id: world.generate_id())
    })
  let room = world.Room(..room, items: update)

  State(room:, system_tables:, self:)
  |> actor.initialised()
  |> actor.selecting(process.new_selector() |> process.select(self))
  |> actor.returning(self)
  |> Ok
}

fn recv(state: State, msg: RoomMessage) -> actor.Next(State, RoomMessage) {
  let state = case msg {
    event.CharacterToRoom(event) -> route_from_character(state, event)
    event.PollRoom(event) -> poll_room(state, event)
    event.InterRoom(event) -> route_from_zone(state, event)
    event.MobileCleanup(mobile_id) -> {
      // clean up crashed mobile
      let world.Room(characters:, ..) as room = state.room
      let characters =
        list.filter(characters, fn(character) { mobile_id != character.id })
      let update = world.Room(..room, characters:)
      State(..state, room: update)
    }
    event.SpawnItem(item_instance) -> {
      let world.Room(items:, ..) as room = state.room
      State(..state, room: world.Room(..room, items: [item_instance, ..items]))
    }
    event.RoomToRoom(..) -> state
  }

  actor.continue(state)
}

fn route_from_character(
  state: State,
  event: Event(event.CharacterToRoomEvent, event.CharacterMessage),
) -> State {
  let State(room:, system_tables:, self:) = state
  let builder = response.new(room, event.from, self, system_tables)
  let builder = case event.data {
    event.MoveRequest(data) -> move_event.request(builder, event, data)
    event.MoveArrive(data) -> move_event.arrive(builder, event, data)
    event.Look -> look_event.room_look(builder, event)
    event.LookAt(data) -> look_event.look_at(builder, event, data)
    event.RejoinRoom -> move_event.rejoin(builder, event)
    event.DoorToggle(data) -> door_event.request(builder, event, data)
    event.DoorUpdateEnd(data) -> door_event.update(builder, event, data)
    event.RoomCommunication(data) -> comm_event.broadcast(builder, event, data)
    event.ItemGet(data) -> item_event.get(builder, event, data)
    event.ItemDrop(data) -> item_event.drop(builder, event, data)
    event.CombatRequest(data) -> combat_event.request(builder, event, data)
  }

  let update =
    builder
    |> response.build()
    |> response.handle_response(room, system_tables)

  State(..state, room: update)
}

fn route_from_zone(
  state: State,
  event: Event(event.InterRoomEvent, event.Done),
) -> State {
  let State(room:, system_tables:, self:) = state
  let builder = response.new(room, event.from, self, system_tables)

  let update =
    case event.data {
      event.MoveDepart(data) -> move_event.depart(builder, event, data)
      event.DoorUpdateBegin(data) ->
        door_event.update(builder, event, data)
        |> response.reply(event.Done)
    }
    |> response.build()
    |> response.handle_response(room, system_tables)

  State(..state, room: update)
}

fn poll_room(
  state: State,
  event: Event(event.PollEvent, world.Vote(world.ErrorRoomRequest)),
) -> State {
  let State(room:, system_tables:, self:) = state
  let builder = response.new(room, event.from, self, system_tables)

  case event.data {
    event.MovePoll(data) -> move_event.vote(builder, event, data)
  }
  |> response.build()
  |> response.handle_response(room, system_tables)

  state
}
