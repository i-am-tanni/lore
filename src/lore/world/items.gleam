//// Stores item data in a flyweight pattern. Instances reference the item data
//// in this table via an id.
////

import gleam/dict.{type Dict}
import gleam/erlang/process
import gleam/list
import gleam/otp/actor
import gleam/result
import glets/table
import logging
import lore/server/my_list
import lore/world.{type Id, type Item, Id}
import lore/world/sql
import pog

pub type Message {
  InsertMany(key_vals: List(#(Id(Item), Item)))
  Insert(item_id: Id(Item), item: Item)
  Delete(item_id: Id(Item))
  ItemInstance(
    caller: process.Subject(Result(world.ItemInstance, Nil)),
    item_id: Id(Item),
  )
}

type State {
  State(
    table_name: process.Name(Message),
    table: table.Set(Id(Item), Item),
    containers: Dict(Int, List(Int)),
  )
}

pub fn start(
  table_name: process.Name(Message),
  db: process.Name(pog.Message),
) -> Result(actor.Started(process.Subject(Message)), actor.StartError) {
  logging.log(logging.Info, "Starting Items table")

  actor.new_with_initialiser(500, fn(self) { init(self, table_name, db) })
  |> actor.named(table_name)
  |> actor.on_message(recv)
  |> actor.start
}

fn init(
  self: process.Subject(Message),
  table_name: process.Name(Message),
  db: process.Name(pog.Message),
) -> Result(actor.Initialised(State, Message, process.Subject(Message)), String) {
  let result = {
    use table <- result.try(
      table_name
      |> table.new
      |> table.set
      |> result.replace_error("Failed to start ets table: 'items'"),
    )
    let db = pog.named_connection(db)
    use returned <- result.try(
      sql.items(db)
      |> result.replace_error("Could not get items from the database!"),
    )
    let pog.Returned(rows: item_rows, ..) = returned
    use pog.Returned(rows: container_kits, ..) <- result.try(
      sql.containers(db)
      |> result.replace_error("Could not get container kits from the database!"),
    )

    // populate table
    let container_kits =
      my_list.group_by(container_kits, fn(container) {
        #(container.container_id, container.item_id)
      })

    list.map(item_rows, fn(row) {
      let item = to_item(row)
      #(item.id, item)
    })
    |> table.insert_many(table, _)
    State(table_name:, table:, containers: container_kits)
    |> Ok
  }

  // We must intercept the error message if the initializer fails and log it
  // otherwise the supervisor will crash with an ugly error message
  // and the error specifics will be lost.
  case result {
    Ok(state) ->
      actor.initialised(state)
      |> actor.returning(self)
      |> Ok

    Error(msg) -> {
      logging.log(logging.Critical, msg)
      Error(msg)
    }
  }
}

fn to_item(row: sql.ItemsRow) -> world.Item {
  let sql.ItemsRow(item_id:, name:, short:, long:, keywords:, ..) = row

  world.Item(
    id: Id(item_id),
    name:,
    short:,
    long:,
    keywords:,
    wear_slot: world.Arms,
    is_container: False,
  )
}

pub fn insert_many(table_name: process.Name(Message), items: List(Item)) -> Nil {
  let items = list.map(items, fn(item) { #(item.id, item) })

  table_name
  |> process.named_subject
  |> process.send(InsertMany(items))
}

pub fn insert(table_name: process.Name(Message), item: Item) -> Nil {
  table_name
  |> process.named_subject
  |> process.send(Insert(item.id, item))
}

/// Load item data
///
pub fn load(
  table_name: process.Name(Message),
  item_id: Id(Item),
) -> Result(Item, Nil) {
  table.lookup(table_name, item_id)
}

pub fn load_from_instance(
  table_name: process.Name(Message),
  item_instance: world.ItemInstance,
) -> Result(Item, world.ErrorItem) {
  case item_instance.item {
    world.Loading(id) ->
      result.replace_error(load(table_name, id), world.InvalidItemId(id))
    world.Loaded(item) -> Ok(item)
  }
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

// Instances are generated as a call to keep table lookups from leaking
// container information.
pub fn instance(
  table_name: process.Name(Message),
  item_id: Id(Item),
) -> Result(world.ItemInstance, Nil) {
  table_name
  |> process.named_subject
  |> process.call(1000, ItemInstance(caller: _, item_id:))
}

/// A basic API for inserting and deleting from the key-val store.
///
fn recv(state: State, msg: Message) -> actor.Next(State, Message) {
  case msg {
    InsertMany(key_vals:) -> table.insert_many(state.table, key_vals)
    Insert(item_id:, item:) -> table.insert(state.table, item_id, item)
    Delete(item_id:) -> table.delete(state.table, item_id)
    ItemInstance(caller:, item_id:) -> {
      item_instance(
        state.table_name,
        world.unwrap_id(item_id),
        state.containers,
      )
      |> actor.send(caller, _)
      True
    }
  }
  actor.continue(state)
}

fn item_instance(
  table_name: process.Name(Message),
  raw_item_id: Int,
  container_kits: Dict(Int, List(Int)),
) -> Result(world.ItemInstance, Nil) {
  use item: Item <- result.try(table.lookup(table_name, Id(raw_item_id)))
  case dict.get(container_kits, raw_item_id) {
    Ok(contents) -> {
      let contains =
        list.filter_map(contents, fn(id) {
          item_instance(table_name, id, container_kits)
        })
        |> world.Contains

      world.ItemInstance(
        id: world.generate_id(),
        item: world.Loading(Id(raw_item_id)),
        keywords: item.keywords,
        contains:,
        was_touched: False,
      )
    }

    Error(Nil) if item.is_container ->
      world.ItemInstance(
        id: world.generate_id(),
        item: world.Loading(Id(raw_item_id)),
        keywords: item.keywords,
        contains: world.Contains([]),
        was_touched: False,
      )

    Error(Nil) ->
      world.ItemInstance(
        id: world.generate_id(),
        item: world.Loading(Id(raw_item_id)),
        keywords: item.keywords,
        contains: world.NotContainer,
        was_touched: False,
      )
  }
  |> Ok
}
