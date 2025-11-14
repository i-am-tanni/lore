import gleam/erlang/process
import gleam/list
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

pub fn item_contains(
  item_table: process.Name(items.Message),
  instances: List(world.ItemInstance),
) -> View {
  case container_contents(item_table, instances) {
    items if items != [] ->
      [view.Leaf("Contains:"), ..items]
      |> view.join("\n")

    _ -> view.Leaf("Contains:\n    Nothing.")
  }
}

pub fn container_contents(
  item_table: process.Name(items.Message),
  instances: List(world.ItemInstance),
) -> List(View) {
  list.filter_map(instances, fn(item_instance) {
    case item_instance.item {
      world.Loading(id) -> items.load(item_table, id)
      world.Loaded(item) -> Ok(item)
    }
  })
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
