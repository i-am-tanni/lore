//// An actor for a player or non-player.
//// Receives input from the endpoint and events from the world, then processes
//// them in request-response cycle.
////

import gleam/bool
import gleam/dict
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/result
import gleam/set.{type Set}
import gleam/string
import gleam/string_tree
import logging
import lore/character/character_registry
import lore/character/conn.{type Conn}
import lore/character/controller.{type Controller}
import lore/character/controller/character_controller
import lore/character/controller/login_controller
import lore/character/controller/spawn_controller
import lore/character/pronoun
import lore/character/view
import lore/character/view/prompt_view
import lore/server/output
import lore/world.{Id, Player}
import lore/world/communication
import lore/world/event.{type CharacterMessage, type Outgoing}
import lore/world/room/room_registry
import lore/world/system_tables
import splitter

const dummy_id = 0

type State {
  /// Halt is the signal to terminate the actor
  State(
    character: world.MobileInternal,
    controller: Controller,
    endpoint: Option(Subject(Outgoing)),
    self: Subject(CharacterMessage),
    cooldown: conn.GlobalCooldown,
    actions: List(event.Action),
    system_tables: system_tables.Lookup,
    subscribed: Set(world.ChatChannel),
    continue: Bool,
  )
}

// Action queue data is held in this struct temporarily before constructing the
// next State.
type ActionSummary {
  ActionSummary(cooldown: conn.GlobalCooldown, actions: List(event.Action))
}

/// When a connection is received, this starts the login sequence.
///
pub fn start_reception(
  endpoint: Subject(Outgoing),
  system_tables: system_tables.Lookup,
) -> Result(actor.Started(Subject(CharacterMessage)), actor.StartError) {
  logging.log(logging.Info, "Player process started")

  let init = init_reception(_, endpoint, system_tables)

  actor.new_with_initialiser(1000, init)
  |> actor.on_message(recv)
  |> actor.start
}

fn init_reception(
  self: process.Subject(CharacterMessage),
  endpoint: Subject(Outgoing),
  system_tables: system_tables.Lookup,
) -> Result(
  actor.Initialised(State, CharacterMessage, Subject(CharacterMessage)),
  String,
) {
  use endpoint_pid <- result.try(
    process.subject_owner(endpoint)
    |> result.replace_error("endpoint has no associated pid."),
  )
  let login_controller =
    controller.LoginFlash(
      score: 0,
      name: "",
      password_hash: "",
      splitter: splitter.new([" ", "\r\n", "\n"]),
      stage: controller.LoginName,
      endpoint: endpoint_pid,
    )
    |> controller.Login

  // Use a fake character to get through login for now.
  //
  let dummy_character =
    world.MobileInternal(
      id: world.generate_id(),
      room_id: Id(dummy_id),
      template_id: Player(Id(dummy_id)),
      name: "",
      role: world.User,
      keywords: [],
      short: "",
      pronouns: pronoun.Feminine,
      inventory: [],
      equipment: dict.new(),
      fighting: world.NoTarget,
      affects: world.affects_init(),
      hp: 20,
      hp_max: 20,
    )

  State(
    self:,
    endpoint: Some(endpoint),
    character: dummy_character,
    controller: login_controller,
    cooldown: conn.FreeToAct,
    actions: [],
    system_tables: system_tables,
    subscribed: set.new(),
    continue: True,
  )
  |> update_controller(login_controller)
  |> actor.initialised
  |> actor.selecting(process.new_selector() |> process.select(self))
  |> actor.returning(self)
  |> Ok
}

/// Starts a new character
///
pub fn start_character(
  data: event.SpawnMobile,
  system_tables system_tables: system_tables.Lookup,
) -> Result(actor.Started(Subject(CharacterMessage)), actor.StartError) {
  let init = init_character(_, data.endpoint, data.mobile, system_tables)

  actor.new_with_initialiser(100, init)
  |> actor.on_message(recv)
  |> actor.start
}

fn init_character(
  self: process.Subject(CharacterMessage),
  endpoint: Option(Subject(Outgoing)),
  character: world.MobileInternal,
  system_tables: system_tables.Lookup,
) -> Result(
  actor.Initialised(State, CharacterMessage, Subject(CharacterMessage)),
  String,
) {
  let spawn_controller =
    controller.SpawnFlash(character.room_id, system_tables.presence)
    |> controller.Spawn()

  character_registry.register(system_tables.character, character.id, self)

  State(
    self:,
    endpoint:,
    character:,
    controller: spawn_controller,
    cooldown: conn.FreeToAct,
    actions: [],
    system_tables: system_tables,
    subscribed: set.new(),
    continue: True,
  )
  |> update_controller(spawn_controller)
  |> actor.initialised()
  |> actor.selecting(process.new_selector() |> process.select(self))
  |> actor.returning(self)
  |> Ok
}

fn recv(
  state: State,
  msg: CharacterMessage,
) -> actor.Next(State, CharacterMessage) {
  let state = case msg {
    event.UserSentCommand(text) ->
      on_controller_message(state, controller.UserSentCommand(text))

    // Only process messages from a room that the character is currently in
    event.RoomSent(received:, from:) if from == state.character.room_id ->
      case received {
        event.RoomSentText(text) ->
          case state.endpoint {
            Some(endpoint) -> {
              // Append prompt and push text to socket
              let prompt =
                prompt_view.prompt(state.character)
                |> view.to_string_tree
                |> output.Text(text: _, newline: False)

              text
              |> list.append([
                output.Text(text: string_tree.new(), newline: True),
                prompt,
              ])
              |> push_text(endpoint, _)

              state
            }
            None -> state
          }

        event.RoomToCharacter(event) ->
          on_controller_message(state, controller.RoomToCharacter(event))
      }

    // ..else if there is a mismatch between the event and the character's
    // present room, DISCARD the event.
    event.RoomSent(..) -> state

    // if cooldown expired, try to process any lazy actions queued
    event.CooldownExpired(id: expected) ->
      case state.cooldown {
        conn.GlobalCooldown(id:, ..) if expected == id ->
          case state.actions {
            [] -> State(..state, cooldown: conn.FreeToAct)

            actions ->
              State(..state, cooldown: conn.FreeToAct)
              |> new_conn()
              |> conn.actions(actions)
              |> conn.to_response
              |> handle_response(state)
          }

        // ..else if an unexpected cooldown expiration notification received,
        // free the character to act and cancel any queued actions to be safe.
        conn.GlobalCooldown(id:, ..) -> {
          let error =
            "Off cooldown but "
            <> string.inspect(id)
            <> " != "
            <> string.inspect(expected)

          logging.log(logging.Error, error)
          State(..state, cooldown: conn.FreeToAct, actions: [])
        }

        // Character is already free to act. In that case, discard notification.
        conn.FreeToAct -> state
      }

    event.Chat(data) -> on_controller_message(state, controller.Chat(data))

    event.ServerRequestedShutdown ->
      new_conn(state)
      |> conn.terminate
      |> conn.to_response
      |> handle_response(state)
  }

  case state.continue {
    True -> actor.continue(state)
    False -> actor.stop()
  }
}

// process a response to a request that was built up by the conn builder
//
fn handle_response(response: conn.Response, state: State) -> State {
  // send output if there is an endpoint and something to send
  case state.endpoint {
    Some(endpoint) -> {
      push_text(endpoint, response.output)
      push_out_of_band(endpoint, response.out_of_band)
    }

    None -> Nil
  }

  // Handle any change over in character
  let reassign_endpoint = case response.next_character {
    Some(character) -> {
      let assert Ok(actor.Started(data: new_subject, ..)) =
        start_character(
          event.SpawnMobile(state.endpoint, character),
          state.system_tables,
        )
      Some(new_subject)
    }

    None -> response.reassign_endpoint
  }

  let halt = response.halt
  // Handle any messages to be sent to the endpoint
  case state.endpoint, reassign_endpoint {
    Some(endpoint), Some(new_subject) -> {
      process.send(endpoint, event.Reassign(new_subject))
      process.send(endpoint, event.Halt(process.self()))
    }

    Some(endpoint), _ if halt ->
      process.send(endpoint, event.Halt(process.self()))

    _, _ -> Nil
  }

  let system_tables = state.system_tables

  // update character
  let character = case response.updated_character {
    Some(update) -> update
    None -> state.character
  }

  // Dispatch chat messages to publish
  let comms = system_tables.communication
  list.each(response.publish, fn(chat_data) {
    let conn.ChatData(channel:, text:) = chat_data
    communication.publish_chat(comms, channel, character.name, text)
  })

  // Dispatch events
  let _ = push_events(response.events, character.room_id, system_tables.room)

  // Get cooldown status and updated action queue information
  let ActionSummary(cooldown:, actions:) = update_actions(response, state)

  let next_controller = response.next_controller
  let controller = case next_controller {
    Some(next) -> next
    None -> response.flash
  }

  let updated_state =
    State(
      self: state.self,
      endpoint: state.endpoint,
      controller:,
      character:,
      cooldown:,
      actions:,
      system_tables:,
      subscribed: response.subscribed,
      continue: state.continue && !halt,
    )

  // update_controller if applicable
  case next_controller {
    Some(next) -> update_controller(updated_state, next)
    None -> updated_state
  }
}

// Pushes text to the endpoint assuming one is available
fn push_text(endpoint: Subject(Outgoing), output: List(output.Text)) -> Nil {
  use <- bool.guard(output == [], Nil)
  actor.send(endpoint, event.PushText(output))
}

fn push_out_of_band(
  endpoint: Subject(Outgoing),
  output: List(output.OutOfBand),
) -> Nil {
  use <- bool.guard(output == [], Nil)
  actor.send(endpoint, event.OutOfBand(output))
}

fn push_events(
  events: List(conn.EventToSend),
  current_room_id: world.Id(world.Room),
  table_name: process.Name(room_registry.Message),
) -> Result(Nil, Nil) {
  let get_room_subject = room_registry.whereis(table_name, current_room_id)
  use current_room_subject <- result.try(get_room_subject)

  list.each(events, fn(event) {
    case event {
      conn.ToRoom(event:) ->
        process.send(current_room_subject, event.CharacterToRoom(event))

      conn.ToRoomId(event:, room_id:) -> {
        case room_registry.whereis(table_name, room_id) {
          Ok(room_subject) ->
            process.send(room_subject, event.CharacterToRoom(event))
          Error(Nil) -> Nil
        }
      }

      conn.ToCharacter(event:, to:, acting_character:) ->
        event.Event(data: event, from: current_room_subject, acting_character:)
        |> event.RoomToCharacter
        |> event.RoomSent(from: current_room_id)
        |> process.send(to, _)
    }
  })
  |> Ok
}

fn update_controller(state: State, next_controller: Controller) -> State {
  new_conn(state)
  |> init_controller(next_controller)
  |> conn.to_response
  |> handle_response(state)
}

// returns updated action queue information based on response
//
fn update_actions(response: conn.Response, state: State) -> ActionSummary {
  let response_actions = response.actions

  case is_cooldown_match(response.cooldown, state.cooldown) {
    // If there was no change in coooldown status and no response actions
    // return state values..
    True if response_actions == [] ->
      ActionSummary(cooldown: state.cooldown, actions: state.actions)

    // ..else if there WERE response actions
    True ->
      ActionSummary(
        cooldown: state.cooldown,
        actions: list.append(state.actions, response_actions),
      )

    // ..else if cooldown status changed,
    // override action queue with actions from response
    False ->
      ActionSummary(cooldown: response.cooldown, actions: response_actions)
  }
}

// Some messages we hand off to the controller to process.
//
fn on_controller_message(state: State, request: controller.Request) -> State {
  new_conn(state)
  |> recv_controller(state.controller, request)
  |> conn.to_response
  |> handle_response(state)
}

// We use static dispatch to route the message to the controller functions
fn init_controller(conn: Conn, controller: controller.Controller) -> Conn {
  case controller {
    controller.Login(flash) -> login_controller.init(conn, flash)
    controller.Character(flash) -> character_controller.init(conn, flash)
    controller.Spawn(flash) -> spawn_controller.init(conn, flash)
  }
}

fn recv_controller(
  conn: Conn,
  controller: controller.Controller,
  msg: controller.Request,
) -> Conn {
  case controller {
    controller.Login(flash) -> login_controller.recv(conn, flash, msg)
    controller.Character(flash) -> character_controller.recv(conn, flash, msg)
    controller.Spawn(_) -> conn
  }
}

fn is_cooldown_match(a: conn.GlobalCooldown, b: conn.GlobalCooldown) -> Bool {
  case a, b {
    conn.FreeToAct, conn.FreeToAct -> True
    conn.GlobalCooldown(id: id1, ..), conn.GlobalCooldown(id: id2, ..) ->
      id1 == id2
    _, _ -> False
  }
}

fn new_conn(state: State) -> Conn {
  let State(
    character:,
    controller: flash,
    self:,
    cooldown:,
    subscribed:,
    system_tables:,
    ..,
  ) = state

  conn.new(character:, flash:, self:, cooldown:, subscribed:, system_tables:)
}
