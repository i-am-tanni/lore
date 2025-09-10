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
import lore/world/sql
import pog

pub type Message =
  cache.Message(Id(Item), Item)

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
    table.Set(Id(Item), Item),
    Message,
    process.Subject(Message),
  ),
  String,
) {
  use table <- result.try(
    table_name
    |> table.new
    |> table.set
    |> result.replace_error("Failed to start ets table: 'items'"),
  )
  use pog.Returned(rows:, ..) <- result.try(
    sql.items(pog.named_connection(db))
    |> result.replace_error("Could not get items from the database!"),
  )

  let items =
    list.map(rows, fn(row) {
      let sql.ItemsRow(item_id:, name:, short:, long:, keywords:) = row
      let id = world.Id(item_id)
      #(id, world.Item(id:, name:, short:, long:, keywords:))
    })
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

pub fn load_items(
  table_name: process.Name(Message),
  instances: List(world.ItemInstance),
) -> List(world.Item) {
  list.filter_map(instances, fn(item_instance) {
    case item_instance.item {
      world.Loading(id) -> load(table_name, id)
      world.Loaded(item) -> Ok(item)
    }
  })
}

pub fn load_instances(
  table_name: process.Name(Message),
  instances: List(world.ItemInstance),
) -> List(world.ItemInstance) {
  list.filter_map(instances, fn(item_instance) {
    case item_instance.item {
      world.Loading(id) -> {
        use item <- result.try(load(table_name, id))
        Ok(world.ItemInstance(..item_instance, item: world.Loaded(item)))
      }

      world.Loaded(_) -> Ok(item_instance)
    }
  })
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
