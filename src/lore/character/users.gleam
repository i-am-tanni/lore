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

/// A message received by the registry process to insert the room subject
/// into the cache keyed by the room instance id.
///
pub type Message {
  /// Insert is called when a character logs in.
  ///
  Insert(pid: process.Pid, id: StringId(Mobile), user: User)

  /// Deregister the subject when a character process goes down.
  ///
  Down(process.Down)
}

type State {
  State(
    table: table.Set(StringId(Mobile), User),
    comms: process.Name(communication.Message),
    ids: Dict(process.Pid, StringId(Mobile)),
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
  connection_pid: process.Pid,
  mobile_id: StringId(Mobile),
  user: User,
) {
  process.named_subject(table_name)
  |> process.send(Insert(connection_pid, mobile_id, user))
}

/// Returns the subject given a registered character instance id.
///
pub fn players_logged_in(table_name: process.Name(Message)) -> List(User) {
  table.to_list(table_name)
  |> list.map(pair.second)
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

  State(table:, comms:, ids: dict.new())
  |> actor.initialised()
  |> actor.selecting(selector)
  |> actor.returning(self)
  |> Ok
}

fn recv(state: State, msg: Message) -> actor.Next(State, Message) {
  let table = state.table
  let result = case msg {
    Insert(pid:, id:, user:) -> {
      use <- bool.guard(result.is_ok(table.lookup(table, id)), Error(Nil))
      table.insert(table, id, user)
      process.monitor(pid)
      let update = dict.insert(state.ids, pid, id)
      Ok(State(..state, ids: update))
    }

    // drop a pid from the table when the process exits
    Down(process.ProcessDown(monitor:, pid:, ..)) -> {
      process.demonitor_process(monitor)
      let ids = state.ids
      use id <- result.try(dict.get(ids, pid))
      table.delete(table, id)
      let update = dict.delete(ids, pid)
      Ok(State(..state, ids: update))
    }

    Down(_) -> Error(Nil)
  }

  case result {
    Ok(update) -> actor.continue(update)
    Error(Nil) -> actor.continue(state)
  }
}
