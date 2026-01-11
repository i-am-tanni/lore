//// Tracks users logged in, connections, disconnections.
////

import gleam/bool
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/otp/actor
import gleam/pair
import gleam/result
import gleam/string
import glets/table
import lore/world.{type Mobile, type StringId}
import lore/world/communication
import lore/world/event

/// A message received by the registry process to insert the room subject
/// into the cache keyed by the room instance id.
///
pub type Message {
  /// Insert is called when a character logs in.
  ///
  Insert(pid: process.Pid, id: StringId(Mobile), name: String)

  /// Deregister the subject when a character process goes down.
  ///
  Down(process.Down)

  NameLookup(
    subject: Subject(event.CharacterMessage),
    reply_to: Subject(String),
  )
}

type State {
  State(
    table: table.Set(String, User),
    comms: process.Name(communication.Message),
    name_lookup: Dict(process.Pid, String),
  )
}

pub type User {
  User(name: String, id: StringId(Mobile))
}

/// Starts the character subject registry.
///
pub fn start(
  table_name: process.Name(Message),
  comms: process.Name(communication.Message),
) -> Result(actor.Started(Subject(Message)), actor.StartError) {
  actor.new_with_initialiser(1000, init(_, table_name, comms))
  |> actor.named(table_name)
  |> actor.on_message(recv)
  |> actor.start
}

/// Registers a list of character subjects keyed by their mobile id
///
pub fn insert(
  table_name: process.Name(Message),
  pid pid: process.Pid,
  name name: String,
  id id: StringId(Mobile),
) {
  let name = string.lowercase(name)
  process.named_subject(table_name)
  |> process.send(Insert(pid:, id:, name:))
}

/// Returns the subject given a registered character instance id.
///
pub fn players_logged_in(table_name: process.Name(Message)) -> List(User) {
  table.to_list(table_name)
  |> list.map(pair.second)
}

pub fn lookup(
  table_name: process.Name(Message),
  name: String,
) -> Result(User, Nil) {
  table.lookup(table_name, name)
}

fn init(
  self: process.Subject(Message),
  table_name: process.Name(Message),
  comms: process.Name(communication.Message),
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

  State(table:, comms:, name_lookup: dict.new())
  |> actor.initialised()
  |> actor.selecting(selector)
  |> actor.returning(self)
  |> Ok
}

fn recv(state: State, msg: Message) -> actor.Next(State, Message) {
  let table = state.table
  let result = case msg {
    Insert(pid:, id:, name:) -> {
      use <- bool.guard(result.is_ok(table.lookup(table, id)), Error(Nil))
      table.insert(table, name, User(id:, name:))
      process.monitor(pid)
      let update = dict.insert(state.name_lookup, pid, name)
      Ok(State(..state, name_lookup: update))
    }

    // drop a pid from the table when the process exits
    Down(process.ProcessDown(monitor:, pid:, ..)) -> {
      process.demonitor_process(monitor)
      let names = state.name_lookup
      use id <- result.try(dict.get(names, pid))
      table.delete(table, id)
      let update = dict.delete(names, pid)
      Ok(State(..state, name_lookup: update))
    }

    Down(_) -> Error(Nil)

    NameLookup(subject:, reply_to:) -> {
      use pid <- result.try(process.subject_owner(subject))
      use name <- result.try(dict.get(state.name_lookup, pid))
      process.send(reply_to, name)
      Ok(state)
    }
  }

  case result {
    Ok(update) -> actor.continue(update)
    Error(Nil) -> actor.continue(state)
  }
}
