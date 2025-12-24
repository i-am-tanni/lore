//// Stores item data in a flyweight pattern. Instances reference the item data
//// in this table via an id.
////

import gleam/dict
import gleam/erlang/process
import gleam/list
import gleam/option.{None, Some}
import gleam/otp/actor
import gleam/result
import glets/cache
import glets/table
import lore/server/my_list
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
  let db = pog.named_connection(db)
  use pog.Returned(rows:, ..) <- result.try(
    sql.items(db)
    |> result.replace_error("Could not get items from the database!"),
  )
  use pog.Returned(rows: containers, ..) <- result.try(
    sql.containers(db)
    |> result.replace_error("Could not get items from the database!"),
  )
  let containers =
    my_list.group_by(containers, fn(container) {
      #(container.container_id, container.item_id)
    })

  let items =
    list.map(rows, fn(row) {
      let sql.ItemsRow(item_id:, name:, short:, long:, keywords:, container_id:) =
        row

      let contains = case container_id {
        Some(container_id) ->
          dict.get(containers, container_id)
          |> result.unwrap([])
          |> list.map(world.Id)
          |> world.Contains

        None -> world.NotContainer
      }

      let id = world.Id(item_id)
      let item = world.Item(id:, name:, short:, long:, keywords:, contains:)
      #(id, item)
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
  use world.Item(id:, keywords:, contains:, ..) <- result.try(cache.lookup(
    table_name,
    item_id,
  ))

  let contains = case contains {
    world.Contains(container_contents) ->
      // generate instances if a container
      list.filter_map(container_contents, instance(table_name, _))
      |> world.Contains

    world.NotContainer -> world.NotContainer
  }

  Ok(world.ItemInstance(
    id: world.generate_id(),
    item: world.Loading(id),
    keywords:,
    contains:,
    was_touched: False,
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
