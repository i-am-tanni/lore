//// A table for tracking pc / Npc locations
//// Upon restart characters can lookup their location previous to the crash.
////
//// ## Automatic cleanup
////
//// If a character crashes a timeout begins and if the character does not
//// restart during the time frame, the room will remove the character info.
////

import gleam/dict.{type Dict}
import gleam/erlang/process
import gleam/otp/actor
import gleam/result
import gleam/string
import glets/table
import lore/world.{type Id, type Mobile, type Room, type StringId}
import lore/world/event
import lore/world/room/room_registry

pub type Message {
  Update(
    subject: process.Subject(event.CharacterMessage),
    mobile_id: StringId(Mobile),
    room_id: Id(Room),
  )

  Down(process.Down)

  /// Mobiel restarted after a crash. False alarm.
  ///
  MobileRestarted(
    subject: process.Subject(event.CharacterMessage),
    mobile_id: StringId(Mobile),
  )

  /// Character crashed and never restarted.
  ///
  RestartTimeoutElapsed(mobile_id: StringId(Mobile), room_id: Id(Room))
}

type State {
  /// Restart timeouts begin in the event a character exits abnormally
  /// If a restart timeout elapses, the presence table notifies the room the
  /// character process is dead and that character should be removed.
  ///
  State(
    self: process.Subject(Message),
    table: table.Set(StringId(Mobile), Id(Room)),
    mobile_id_lookup: Dict(process.Pid, StringId(Mobile)),
    room_registry: process.Name(room_registry.Message),
    restart_timeouts: Dict(StringId(Mobile), process.Timer),
  )
}

const timeout_ms = 1000

/// Starts the room subject registry.
///
pub fn start(
  table_name: process.Name(Message),
  room_registry: process.Name(room_registry.Message),
) -> Result(actor.Started(process.Subject(Message)), actor.StartError) {
  actor.new_with_initialiser(100, fn(self) {
    init(self, table_name, room_registry)
  })
  |> actor.named(table_name)
  |> actor.on_message(recv)
  |> actor.start
}

fn init(
  self: process.Subject(Message),
  table_name: process.Name(Message),
  room_registry: process.Name(room_registry.Message),
) -> Result(actor.Initialised(State, Message, process.Subject(Message)), String) {
  let start_table =
    table_name
    |> table.new
    |> table.set
    |> result.replace_error(
      "Failed to start ets table: " <> string.inspect(table_name),
    )

  use table <- result.try(start_table)
  let selector =
    process.new_selector()
    |> process.select_monitors(fn(down) { Down(down) })
    |> process.select(self)

  State(
    self:,
    table:,
    room_registry:,
    mobile_id_lookup: dict.new(),
    restart_timeouts: dict.new(),
  )
  |> actor.initialised
  |> actor.selecting(selector)
  |> actor.returning(self)
  |> Ok
}

/// Returns the room id given a registered room instance id.
///
pub fn lookup(
  table_name: process.Name(Message),
  mobile_id: StringId(Mobile),
) -> Result(Id(Room), Nil) {
  table.lookup(table_name, mobile_id)
}

/// Updates a character location
pub fn update(
  table_name: process.Name(Message),
  subject: process.Subject(event.CharacterMessage),
  mobile_id: StringId(Mobile),
  room_id: Id(Room),
) -> Nil {
  process.named_subject(table_name)
  |> process.send(Update(subject:, mobile_id:, room_id:))
}

/// Notifies the presence process that a character restarted so it can be
/// monitored and timeouts cancelled.
///
pub fn notify_restart(
  table_name: process.Name(Message),
  subject: process.Subject(event.CharacterMessage),
  mobile_id: StringId(Mobile),
) -> Nil {
  process.named_subject(table_name)
  |> process.send(MobileRestarted(subject:, mobile_id:))
}

fn recv(state: State, msg: Message) -> actor.Next(State, Message) {
  let table = state.table
  let result = case msg {
    Update(subject:, mobile_id:, room_id:) -> {
      case table.has_key(table, mobile_id) {
        True -> {
          table.insert(table, mobile_id, room_id)
          Ok(state)
        }
        False -> {
          table.insert(table, mobile_id, room_id)
          monitor_subject(state, subject, mobile_id)
        }
      }
    }

    Down(process.ProcessDown(monitor:, pid:, reason:)) ->
      handle_down(state, monitor, pid, reason)

    // cancel timeout and monitor new subject
    MobileRestarted(subject:, mobile_id:) -> {
      let restart_timeouts = state.restart_timeouts
      use timer <- result.try(dict.get(restart_timeouts, mobile_id))
      process.cancel_timer(timer)
      let restart_timeouts = dict.delete(restart_timeouts, mobile_id)
      State(..state, restart_timeouts:)
      |> monitor_subject(subject, mobile_id)
    }

    // If character crashed and never restarted, delete table info and notify
    // room for clean up.
    //
    RestartTimeoutElapsed(mobile_id:, room_id:) -> {
      table.delete(state.table, mobile_id)
      let update = dict.delete(state.restart_timeouts, mobile_id)
      case room_registry.whereis(state.room_registry, room_id) {
        Ok(room_subject) ->
          process.send(room_subject, event.MobileCleanup(mobile_id))
        Error(Nil) -> Nil
      }
      Ok(State(..state, restart_timeouts: update))
    }

    // Unexpected
    Down(process.PortDown(..)) -> Error(Nil)
  }

  case result {
    Ok(update) -> actor.continue(update)
    Error(Nil) -> actor.continue(state)
  }
}

/// Character exited.
/// If not a crash, delete tracking.
/// Else, start a restart timeout.
///
fn handle_down(
  state: State,
  monitor: process.Monitor,
  pid: process.Pid,
  reason: process.ExitReason,
) -> Result(State, Nil) {
  process.demonitor_process(monitor)
  let mobile_id_lookup = state.mobile_id_lookup
  use mobile_id <- result.try(dict.get(mobile_id_lookup, pid))
  use room_id <- result.try(table.lookup(state.table, mobile_id))
  case reason {
    process.Normal | process.Killed -> {
      table.delete(state.table, mobile_id)
      let update = dict.delete(mobile_id_lookup, pid)
      case room_registry.whereis(state.room_registry, room_id) {
        Ok(room_subject) ->
          process.send(room_subject, event.MobileCleanup(mobile_id))
        Error(Nil) -> Nil
      }
      Ok(State(..state, mobile_id_lookup: update))
    }

    // Character crashed. Start a restart timeout.
    // If timeout elapses, clean up, otherwise monitor restarted character.
    process.Abnormal(..) -> {
      let message = RestartTimeoutElapsed(mobile_id:, room_id:)
      let timer = process.send_after(state.self, timeout_ms, message)
      let mobile_id_lookup = dict.delete(mobile_id_lookup, pid)
      let restart_timeouts =
        dict.insert(state.restart_timeouts, mobile_id, timer)
      Ok(State(..state, restart_timeouts:, mobile_id_lookup:))
    }
  }
}

fn monitor_subject(
  state: State,
  subject: process.Subject(event.CharacterMessage),
  mobile_id: StringId(Mobile),
) -> Result(State, Nil) {
  use pid <- result.try(process.subject_owner(subject))
  // We don't store the monitor because we will get it in the down message
  process.monitor(pid)
  let update = dict.insert(state.mobile_id_lookup, pid, mobile_id)
  Ok(State(..state, mobile_id_lookup: update))
}
