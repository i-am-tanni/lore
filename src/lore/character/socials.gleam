import gleam/erlang/process
import gleam/list
import gleam/otp/actor
import gleam/result
import glets/cache
import glets/table
import lore/world/sql
import pog

pub type Social {
  Social(
    command: String,
    char_auto: String,
    char_found: String,
    char_no_arg: String,
    others_auto: String,
    others_found: String,
    others_no_arg: String,
    victim_found: String,
  )
}

pub type Message =
  cache.Message(String, Social)

pub fn start(
  table_name: process.Name(Message),
  db: process.Name(pog.Message),
) -> Result(actor.Started(process.Subject(Message)), actor.StartError) {
  actor.new_with_initialiser(500, fn(self) { init(self, table_name, db) })
  |> actor.named(table_name)
  |> actor.on_message(recv)
  |> actor.start
}

fn init(
  self: process.Subject(Message),
  table_name: process.Name(Message),
  db: process.Name(pog.Message),
) -> Result(
  actor.Initialised(
    table.Set(String, Social),
    Message,
    process.Subject(Message),
  ),
  String,
) {
  use table <- result.try(
    table_name
    |> table.new
    |> table.set
    |> result.replace_error("Failed to start ets table: 'socials'."),
  )
  use pog.Returned(rows:, ..) <- result.try(
    sql.socials(pog.named_connection(db))
    |> result.replace_error("Could not get socials from the database!"),
  )

  let socials =
    list.map(rows, fn(row) {
      let command = row.command
      let social =
        Social(
          command:,
          char_auto: row.char_auto,
          char_no_arg: row.char_no_arg,
          char_found: row.char_found,
          others_auto: row.others_auto,
          others_found: row.others_found,
          others_no_arg: row.others_no_arg,
          victim_found: row.vict_found,
        )
      #(command, social)
    })
  table.insert_many(table, socials)

  table
  |> actor.initialised
  |> actor.returning(self)
  |> Ok
}

/// Registers as list of room subjects keyed by their room instance id
/// 
pub fn insert(
  table_name: process.Name(Message),
  command: String,
  social: Social,
) -> Nil {
  table_name
  |> process.named_subject
  |> process.send(cache.Insert(command, social))
}

pub fn delete(table_name: process.Name(Message), command: String) {
  process.named_subject(table_name)
  |> process.send(cache.Delete(command))
}

/// Returns the subject given a registered room instance id.
/// 
pub fn lookup(
  table_name: process.Name(Message),
  command: String,
) -> Result(Social, Nil) {
  cache.lookup(table_name, command)
}

/// A basic API for inserting and deleting from the key-val store.
/// 
fn recv(
  table: table.Set(String, Social),
  msg: Message,
) -> actor.Next(table.Set(String, Social), Message) {
  case msg {
    cache.InsertMany(objects:) -> table.insert_many(table, objects)
    cache.Insert(key:, val:) -> table.insert(table, key, val)
    cache.Delete(key:) -> table.delete(table, key)
  }
  actor.continue(table)
}
