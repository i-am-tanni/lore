import gleam/dict
import gleam/erlang/process
import gleam/list
import gleam/result
import lore/character/view.{type View}
import lore/character/view/character_view
import lore/world
import lore/world/items

pub fn inventory(
  item_table: process.Name(items.Message),
  self: world.MobileInternal,
) -> View {
  case container_contents(item_table, self.inventory) {
    items if items != [] ->
      [view.Leaf("You are carrying:"), ..items]
      |> view.join("\n")

    _ -> view.Leaf("You are carrying:\n    Nothing.")
  }
}

pub fn equipment(
  item_table: process.Name(items.Message),
  self: world.MobileInternal,
) -> View {
  let equipment = self.equipment
  let is_naked =
    dict.is_empty(equipment)
    || list.all(dict.values(equipment), fn(wearing) {
      wearing == world.EmptySlot
    })

  let equipment =
    equipment
    |> dict.to_list
    |> list.filter_map(fn(key_val) {
      let #(wear_slot, wearing) = key_val
      let wear_slot = wear_slot_to_string(wear_slot)
      case wearing {
        world.Wearing(item_instance) ->
          item_load(item_table, item_instance)
          |> result.map(fn(item) { view.Leaves([wear_slot, ": ", item.name]) })

        world.EmptySlot ->
          [
            wear_slot,
            ": Empty",
          ]
          |> view.Leaves
          |> Ok
      }
    })

  let prelude = case is_naked {
    True -> ["You are NAKED!"] |> view.Leaves
    False -> ["You are wearing:"] |> view.Leaves
  }

  view.join([prelude, ..equipment], "\n")
}

pub fn item_contains(
  item_table: process.Name(items.Message),
  instances: List(world.ItemInstance),
) -> View {
  case container_contents(item_table, instances) {
    items if items != [] ->
      [view.Leaf("You look inside and see:"), ..items]
      |> view.join("\n")

    _ -> view.Leaf("You look inside and see:\n    Nothing.")
  }
}

pub fn container_contents(
  item_table: process.Name(items.Message),
  instances: List(world.ItemInstance),
) -> List(View) {
  list.filter_map(instances, item_load(item_table, _))
  |> list.map(fn(item) { view.Leaves(["  ", item.name]) })
}

pub fn get(
  self: world.MobileInternal,
  acting_character: world.Mobile,
  item: world.Item,
) -> View {
  case view.perspective_simple(self, acting_character) {
    view.Self -> ["You get ", item.name, "."]
    view.Witness -> [
      character_view.name(acting_character),
      " gets ",
      item.name,
    ]
  }
  |> view.Leaves
}

pub fn drop(
  self: world.MobileInternal,
  acting_character: world.Mobile,
  item: world.Item,
) -> View {
  case view.perspective_simple(self, acting_character) {
    view.Self -> ["You drop ", item.name, "."]
    view.Witness -> [
      character_view.name(acting_character),
      " drops ",
      item.name,
    ]
  }
  |> view.Leaves
}

pub fn inspect(item: world.Item) -> View {
  [item.name, "\n  ", item.long] |> view.Leaves
}

pub fn spawn_item(item: world.Item) -> View {
  [
    "You weave stray threads of light together, manifesting ",
    item.name,
    " from the ether.",
  ]
  |> view.Leaves
}

pub fn item_wear(item: world.Item) -> View {
  view.Leaves(["You wear ", item.name, "."])
}

pub fn item_remove(
  items_table: process.Name(items.Message),
  item: world.ItemInstance,
) -> View {
  case item_load(items_table, item) {
    Ok(item) -> view.Leaves(["You take off ", item.name, "."])
    Error(Nil) -> view.Leaf("Unable to load item name.")
  }
}

pub fn wear_slot_to_string(wear_slot: world.WearSlot) -> String {
  case wear_slot {
    world.Arms -> "arms"
    world.CannotWear -> "error"
  }
}

fn item_load(
  item_table: process.Name(items.Message),
  item_instance: world.ItemInstance,
) -> Result(world.Item, Nil) {
  case item_instance.item {
    world.Loading(item_id) -> items.load(item_table, item_id)
    world.Loaded(item) -> Ok(item)
  }
}
