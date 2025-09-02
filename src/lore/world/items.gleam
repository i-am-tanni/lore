//// Stores item data in a flyweight pattern. Instances reference the item data
//// in this table via an id.
//// 

import gleam/erlang/process
import gleam/list
import gleam/otp/actor
import gleam/result
import glets/cache
import glets/table
import lore/world.{type Id, type Item}

pub type Message =
  cache.Message(Id(Item), Item)

pub fn start(
  table_name: process.Name(Message),
  items: List(Item),
) -> Result(actor.Started(process.Subject(Message)), actor.StartError) {
  actor.new_with_initialiser(500, fn(self) { init(self, table_name, items) })
  |> actor.named(table_name)
  |> actor.on_message(recv)
  |> actor.start
}

fn init(
  self: process.Subject(Message),
  table_name: process.Name(Message),
  items: List(Item),
) -> Result(
  actor.Initialised(
    table.Set(Id(Item), Item),
    Message,
    process.Subject(Message),
  ),
  String,
) {
  let start_table =
    table_name
    |> table.new
    |> table.set
    |> result.replace_error("Failed to start ets table: 'items'")

  use table <- result.try(start_table)
  let items = list.map(items, fn(item) { #(item.id, item) })
  table.insert_many(table, items)

  table
  |> actor.initialised
  |> actor.returning(self)
  |> Ok
}

pub fn insert_many(table_name: process.Name(Message), items: List(Item)) -> Nil {
  let items = list.map(items, fn(item) { #(item.id, item) })

  table_name
  |> process.named_subject
  |> process.send(cache.InsertMany(items))
}

pub fn insert(table_name: process.Name(Message), item: Item) -> Nil {
  table_name
  |> process.named_subject
  |> process.send(cache.Insert(item.id, item))
}

/// Load item data
/// 
pub fn load(
  table_name: process.Name(Message),
  item_id: Id(Item),
) -> Result(Item, Nil) {
  cache.lookup(table_name, item_id)
}

/// Generate an item instance given an item id
/// 
pub fn instance(
  table_name: process.Name(Message),
  item_id: Id(Item),
) -> Result(world.ItemInstance, Nil) {
  use world.Item(id:, keywords:, ..) <- result.try(cache.lookup(
    table_name,
    item_id,
  ))
  Ok(world.ItemInstance(
    id: world.generate_id(),
    item: world.Loading(id),
    keywords:,
  ))
}

/// A basic API for inserting and deleting from the key-val store.
/// 
fn recv(
  table: table.Set(Id(Item), Item),
  msg: Message,
) -> actor.Next(table.Set(Id(Item), Item), Message) {
  case msg {
    cache.InsertMany(objects:) -> table.insert_many(table, objects)
    cache.Insert(key:, val:) -> table.insert(table, key, val)
    cache.Delete(key:) -> table.delete(table, key)
  }
  actor.continue(table)
}
