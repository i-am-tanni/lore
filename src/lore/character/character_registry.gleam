//// A registry for character mailboxes.
////

import gleam/bool
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import gleam/result
import gleam/string
import glets/table
import lore/world.{type Mobile, type StringId}
import lore/world/event.{type CharacterMessage}

pub type Message {
  /// Register is called when a character process initializes or restarts.
  ///
  Register(id: StringId(Mobile), subject: Subject(CharacterMessage))

  /// Deregister the subject when a character process goes down.
  ///
  Deregister(process.Down)
}

type State {
  // When a process goes down, the Id is looked up via the Id dict to then
  // be removed from the table
  //
  State(
    table: table.Set(StringId(Mobile), Subject(CharacterMessage)),
    ids: Dict(process.Pid, StringId(Mobile)),
  )
}

/// Starts the character subject registry.
///
pub fn start(
  table_name: process.Name(Message),
) -> Result(actor.Started(Subject(Message)), actor.StartError) {
  actor.new_with_initialiser(1000, init(_, table_name))
  |> actor.named(table_name)
  |> actor.on_message(recv)
  |> actor.start
}

/// Registers a list of character subjects keyed by their mobile id
///
pub fn register(
  table_name: process.Name(Message),
  mobile_id: StringId(Mobile),
  subject: process.Subject(CharacterMessage),
) {
  process.named_subject(table_name)
  |> process.send(Register(mobile_id, subject))
}

/// Returns the subject given a registered character instance id.
///
pub fn whereis(
  table_name: process.Name(Message),
  mobile_id: StringId(Mobile),
) -> Result(process.Subject(CharacterMessage), Nil) {
  table.lookup(table_name, mobile_id)
}

fn init(
  self: process.Subject(Message),
  table_name: process.Name(Message),
) -> Result(actor.Initialised(State, Message, process.Subject(Message)), String) {
  let start_table =
    table_name
    |> table.new
    |> table.set
    |> result.replace_error(
      "Failed to start ets table: " <> string.inspect(table_name),
    )

  use table <- result.try(start_table)

  // If subscriber exits or crashes, monitor in order to drop pid from tables.
  // This prevents a memory leak over time as dead mailboxes accumulate.
  let selector =
    process.new_selector()
    |> process.select_monitors(fn(down) { Deregister(down) })
    |> process.select(self)

  State(table: table, ids: dict.new())
  |> actor.initialised()
  |> actor.selecting(selector)
  |> actor.returning(self)
  |> Ok
}

fn recv(state: State, msg: Message) -> actor.Next(State, Message) {
  let result = case msg {
    Register(id:, subject:) -> {
      use pid <- result.try(process.subject_owner(subject))
      let State(table:, ids:) = state
      table.insert(table, id, subject)
      // If pid is new, add monitoring so clean up can be auto-performed
      //   when pid exits.
      use <- bool.guard(dict.has_key(ids, pid), Ok(state))
      process.monitor(pid)
      let update = dict.insert(ids, pid, id)
      Ok(State(table:, ids: update))
    }

    // drop a pid from the table when the process exits
    Deregister(process.ProcessDown(monitor:, pid:, ..)) -> {
      process.demonitor_process(monitor)
      let State(table:, ids:) = state
      use id <- result.try(dict.get(ids, pid))
      table.delete(table, id)
      let update = dict.delete(ids, pid)
      Ok(State(table:, ids: update))
    }

    Deregister(_) -> Error(Nil)
  }

  case result {
    Ok(update) -> actor.continue(update)
    Error(_) -> actor.continue(state)
  }
}
