import gleam/erlang/process
import gleam/list
import gleam/string_tree
import lore/character/view.{type View}
import lore/character/view/character_view
import lore/world
import lore/world/items

pub fn inventory(
  item_table: process.Name(items.Message),
  self: world.MobileInternal,
) -> View {
  let items =
    list.filter_map(self.inventory, fn(item_instance) {
      case item_instance.item {
        world.Loading(id) -> items.load(item_table, id)
        world.Loaded(item) -> Ok(item)
      }
    })
    |> list.map(fn(item) { string_tree.from_strings(["  ", item.name]) })

  case items != [] {
    True ->
      [string_tree.from_string("You are carrying:"), ..items]
      |> string_tree.join("\n")
      |> view.Tree

    False -> view.Leaf("You are carrying:\n    Nothing.")
  }
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
