//// An actor for a player or non-player.
//// 

import gleam/erlang/process.{type Subject}
import gleam/function.{tap}
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import logging
import ming/character/character_registry
import ming/character/conn.{type Conn}
import ming/character/controller.{type Flash}
import ming/server/output.{type Outgoing, Halt, PushText}
import ming/world.{
  type CharacterMessage, type ControllerMessage, type Mobile, Mobile, Player,
  Trimmed,
}
import ming/world/id.{type Id, Id}

type State {
  State(
    protocol: Option(Subject(Outgoing)),
    character: Mobile,
    flash: Flash,
    recv: fn(Conn, ControllerMessage) -> Conn,
  )
}

/// A staged transition to a new controller.
/// 
pub type NextController {
  /// The init function takes a Conn and a new flash as arguments, but the old
  /// flash still accessible via `conn.get_flash()`
  /// 
  NextController(
    flash: Flash,
    init: fn(Conn, Flash) -> Conn,
    recv: fn(Conn, ControllerMessage) -> Conn,
  )
}

/// When a connection is received, start a new player.
/// 
pub fn start_player(
  protocol: Subject(Outgoing),
  init controller: conn.NextController,
) {
  logging.log(logging.Info, "Player process started")

  let state =
    State(
      protocol: Some(protocol),
      character: temp_character(),
      flash: controller.flash,
      recv: controller.recv,
    )

  state
  |> update_controller(controller)
  |> actor.start(handle_message)
}

fn handle_message(
  msg: CharacterMessage,
  state: State,
) -> actor.Next(CharacterMessage, State) {
  case msg {
    world.RoomSentText(text) -> {
      tap(state, push_text(_, text))
      |> actor.continue()
    }
    world.ToController(msg) -> {
      conn.new(state.character, state.flash)
      |> state.recv(msg)
      |> conn.to_response()
      |> handle_response(state, _)
      |> actor.continue()
    }
  }
}

fn handle_response(state: State, response: conn.Response) -> State {
  // send output if there is a protocol and something to send
  push_text(state, response.output)

  // handle any halting requests
  case state.protocol, response.halt {
    Some(protocol), True -> actor.send(protocol, Halt)
    _, _ -> Nil
  }

  // update character
  let state = case response.updated_character {
    Some(update) -> State(..state, character: update)
    None -> state
  }

  // update flash
  let state = case response.updated_flash {
    Some(update) -> State(..state, flash: update)
    None -> state
  }

  // update_controller
  case response.next_controller {
    Some(next) -> update_controller(state, next)
    None -> state
  }
}

fn push_text(state: State, output: List(output.Text)) -> Nil {
  case state.protocol, output {
    Some(protocol), output if output != [] ->
      actor.send(protocol, PushText(output))
    _, _ -> Nil
  }
}

fn update_controller(
  state: State,
  next_controller: conn.NextController,
) -> State {
  let conn.NextController(flash: new_flash, init:, recv:) = next_controller
  let State(flash: old_flash, character:, ..) = state
  let state = State(..state, recv: recv)

  conn.new(character, old_flash)
  |> init(new_flash)
  |> conn.to_response()
  |> handle_response(state, _)
}

fn temp_character() -> Mobile {
  Mobile(
    id: Id(0),
    room_id: Id(0),
    template: Player,
    name: "",
    keywords: [],
    short: "",
    private: Trimmed,
  )
}

pub fn whereis(id: Id(Mobile)) -> Result(Subject(CharacterMessage), Nil) {
  character_registry.whereis(id)
}
