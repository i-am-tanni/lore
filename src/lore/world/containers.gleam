//// A key-val store for container contents keyed by a container_id.
////

import gleam/erlang/process
import gleam/result
import glets/cache
import lore/server/my_list
import lore/world.{type Id, type ItemInstance}

pub type Message =
  cache.Message(Id(ItemInstance), List(ItemInstance))

/// Public Interface
///
pub fn load(
  table_name: process.Name(Message),
  container_id: Id(ItemInstance),
) -> Result(List(ItemInstance), Nil) {
  cache.lookup(table_name, container_id)
}

pub fn prepend(
  table_name: process.Name(Message),
  container_id: Id(ItemInstance),
  element: ItemInstance,
) -> Bool {
  let result = {
    use contents <- result.try(cache.lookup(table_name, container_id))
    let updated = [element, ..contents]
    process.named_subject(table_name)
    |> process.send(cache.Insert(container_id, updated))
    Ok(True)
  }

  result.unwrap(result, False)
}

pub fn new(
  table_name: process.Name(Message),
  container_id: Id(ItemInstance),
  elements: List(ItemInstance),
) -> Result(Id(ItemInstance), Nil) {
  case cache.lookup(table_name, container_id) {
    Ok(_) -> Error(Nil)
    Error(_) -> {
      process.named_subject(table_name)
      |> process.send(cache.Insert(container_id, elements))
      Ok(container_id)
    }
  }
}

pub fn delete(
  table_name: process.Name(Message),
  container_id: Id(ItemInstance),
) -> Nil {
  process.named_subject(table_name)
  |> process.send(cache.Delete(container_id))
}

pub fn pop_nth(
  table_name: process.Name(Message),
  container_id: Id(ItemInstance),
  ordinal: Int,
  matching: fn(ItemInstance) -> Bool,
) -> Result(ItemInstance, Nil) {
  use instances <- result.try(cache.lookup(table_name, container_id))
  use #(instance, filtered) <- result.try(my_list.pop_nth_match(
    instances,
    ordinal,
    matching,
  ))

  process.named_subject(table_name)
  |> process.send(cache.Insert(container_id, filtered))
  Ok(instance)
}
