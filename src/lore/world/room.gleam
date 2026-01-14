/// An actor for a room process, which serves as a synchronization point
/// for physical actions and tracks the room state.
///
import gleam/dict
import gleam/erlang/process.{type Subject}
import gleam/float
import gleam/function
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/otp/actor
import gleam/result
import gleam/time/timestamp
import lore/character/character_registry
import lore/server/my_list
import lore/server/output
import lore/world.{type Room}
import lore/world/communication
import lore/world/event.{type Event, type RoomMessage}
import lore/world/room/events/combat_event
import lore/world/room/events/comm_event
import lore/world/room/events/door_event
import lore/world/room/events/item_event
import lore/world/room/events/look_event
import lore/world/room/events/move_event
import lore/world/room/response.{type Response, Response}
import lore/world/room/room_registry
import lore/world/system_tables
import lore/world/zone/zone_registry

const combat_round_len_in_ms = 3000

type Timer {
  Timer(process.Timer)
  Cancelled
}

type State {
  State(
    room: world.Room,
    system_tables: system_tables.Lookup,
    self: process.Subject(RoomMessage),
    combat_queue: List(event.CombatPollData),
    combat_timer: Timer,
    is_in_combat: Bool,
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

  State(
    room:,
    system_tables:,
    self:,
    combat_queue: [],
    combat_timer: Cancelled,
    is_in_combat: False,
  )
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
      // clean up dead or crashed mobile
      let world.Room(characters:, ..) as room = state.room
      let characters =
        list.filter(characters, fn(character) { mobile_id != character.id })
      let update = world.Room(..room, characters:)
      State(..state, room: update)
    }

    event.SpawnItem(item_instance) -> {
      let world.Room(items:, ..) as room = state.room
      case item_exists(items, item_instance) {
        True -> state
        False ->
          State(
            ..state,
            room: world.Room(..room, items: [item_instance, ..items]),
          )
      }
    }

    event.DespawnItems(item_ids) -> {
      let world.Room(items:, ..) as room = state.room
      let filtered =
        list.filter(items, fn(item) {
          let item_id = item.id
          !list.any(item_ids, fn(id) { id == item_id })
        })

      let room = world.Room(..room, items: filtered)
      State(..state, room:)
    }

    event.RoomToRoom(..) -> state
    event.CombatRoundTrigger -> {
      let state = State(..state, combat_timer: Cancelled)
      let builder = to_builder_room_msg(state)

      let #(round_actions, builder) = response.round_flush(builder)
      combat_event.round_trigger(builder, round_actions)
      |> response.build
      |> handle_response(state, _)
    }
  }

  actor.continue(state)
}

fn route_from_character(
  state: State,
  event: Event(event.CharacterToRoomEvent, event.CharacterMessage),
) -> State {
  let builder = to_builder(state, event)
  let builder = case event.data {
    event.MoveRequest(data) -> move_event.request(builder, event, data)
    event.TeleportRequest(data) ->
      move_event.request_teleport(builder, event, data)
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

  builder
  |> response.build
  |> handle_response(state, _)
}

fn route_from_zone(
  state: State,
  event: Event(event.InterRoomEvent, event.Done),
) -> State {
  let builder = to_builder(state, event)

  case event.data {
    event.MoveDepart(data) -> move_event.depart(builder, event, data)
    event.DoorUpdateBegin(data) ->
      door_event.update(builder, event, data)
      |> response.reply(event.Done)
  }
  |> response.build
  |> handle_response(state, _)
}

fn poll_room(
  state: State,
  event: Event(event.PollEvent, world.Vote(world.ErrorRoomRequest)),
) -> State {
  let builder = to_builder(state, event)

  case event.data {
    event.MovePoll(data) -> move_event.vote(builder, event, data)
  }
  |> response.build
  |> handle_response(state, _)

  state
}

fn to_builder_room_msg(state: State) -> response.Builder(RoomMessage) {
  let State(room:, system_tables:, self:, combat_queue:, is_in_combat:, ..) =
    state

  response.new(
    room,
    self,
    self,
    None,
    system_tables,
    combat_queue,
    is_in_combat,
  )
}

fn to_builder(state: State, event: Event(b, c)) -> response.Builder(c) {
  let State(room:, system_tables:, self:, combat_queue:, is_in_combat:, ..) =
    state

  response.new(
    room,
    event.from,
    self,
    Some(event.acting_character),
    system_tables,
    combat_queue,
    is_in_combat,
  )
}

/// Process a response to a RoomEvent and commit staged state changes.
///
fn handle_response(state: State, response: Response(c)) -> State {
  let room = state.room
  // Send outputs
  send_text(response.output, room)
  list.each(response.events, send_event(_, room, state.system_tables))

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

  let combat_timer = {
    let is_in_combat = response.is_in_combat

    case state.combat_timer {
      Cancelled if is_in_combat ->
        schedule_combat_round(state.self, combat_round_len_in_ms)

      Timer(timer) if !is_in_combat -> {
        process.cancel_timer(timer)
        Cancelled
      }

      Timer(_) as timer -> timer

      Cancelled -> Cancelled
    }
  }
  let Response(is_in_combat:, combat_queue:, ..) = response
  let room = world.Room(..room, characters:, items:, exits:)
  State(..state, room:, combat_timer:, combat_queue:, is_in_combat:)
}

fn send_text(
  output: List(#(Subject(event.CharacterMessage), output.Text)),
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
  event: response.EventToSend(a),
  from room: world.Room,
  lookup system_tables: system_tables.Lookup,
) -> Nil {
  case event {
    response.Reply(to:, message:) -> process.send(to, message)

    response.ToCharacter(subject:, event:) ->
      process.send(
        subject,
        event.RoomSent(event.RoomToCharacter(event), room.id),
      )

    response.ToCharacterId(id:, event:) -> {
      case character_registry.whereis(system_tables.character, id) {
        Ok(subject) ->
          process.send(
            subject,
            event.RoomSent(event.RoomToCharacter(event), room.id),
          )

        _ -> Nil
      }
    }

    response.ToZone(id:, event:) ->
      case zone_registry.whereis(system_tables.zone, id) {
        Ok(subject) -> process.send(subject, event.RoomToZone(event))
        _ -> Nil
      }

    response.ToRoom(id:, event:) ->
      case room_registry.whereis(system_tables.room, id) {
        Ok(subject) -> process.send(subject, event.RoomToRoom(event))
        _ -> Nil
      }

    // Sends a room message to all subscribers of the room channel.
    //
    response.Broadcast(channel:, event:) ->
      communication.publish(
        system_tables.communication,
        channel,
        event.RoomSent(event.RoomToCharacter(event), room.id),
      )

    // Warning! Blocks until the table is up-to-date to keep the table in sync
    // for broadcasts.
    response.Subscribe(channel:, subscriber:) -> {
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
    response.Unsubscribe(channel:, subscriber:) -> {
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

fn schedule_combat_round(
  self: process.Subject(RoomMessage),
  combat_round_len_in_ms: Int,
) -> Timer {
  let delay =
    timestamp.system_time()
    |> timestamp.to_unix_seconds
    |> float.multiply(1000.0)
    |> float.truncate
    |> int.modulo(combat_round_len_in_ms)
    |> result.unwrap(0)
    |> int.subtract(combat_round_len_in_ms, _)

  process.send_after(self, delay, event.CombatRoundTrigger)
  |> Timer
}

fn item_exists(
  instances: List(world.ItemInstance),
  reset: world.ItemInstance,
) -> Bool {
  let item_id = world.item_id(reset)
  list.any(instances, fn(instance) { world.item_id(instance) == item_id })
}
