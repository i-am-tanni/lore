/// The database process where all db requests are serialized.
/// 
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/otp/actor
import gleam/result
import gleam/string
import ming/world.{type MobTemplate, type Mobile, type Room}
import ming/world/id.{type Id, Id}
import ming/world/item.{type ItemInstance}
import ming/world/sql
import pog.{type QueryError, Returned}

pub type Message {
  Message
}

pub fn start_repo() -> Result(Subject(Message), actor.StartError) {
  // configure and connect to the db
  let db =
    pog.default_config()
    |> pog.host("localhost")
    |> pog.database("world")
    |> pog.pool_size(15)
    |> pog.connect

  actor.start(db, recv)
}

pub fn recv(
  _msg: Message,
  db: pog.Connection,
) -> actor.Next(Message, pog.Connection) {
  actor.continue(db)
}
