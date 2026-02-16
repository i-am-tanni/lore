import gleam/list
import gleam/option.{None, Some}
import gleam/string_tree.{type StringTree}
import lore/character/flag
import lore/character/view.{type View}
import lore/world.{type Room}
import lore/world/items
import lore/world/mapper
import lore/world/system_tables

const color_room_title = "&189"

const color_reset = "0;"

pub fn room_with_mini_map_impure(
  room: Room,
  observer: world.Mobile,
  lookup: system_tables.Lookup,
) -> View {
  let loaded = items.load_instances(lookup.items, room.items)
  let room = world.Room(..room, items: loaded)
  let mini_map =
    mapper.render_mini_map(lookup.mapper, room.id)
    |> string_tree.join("\n")
    |> string_tree.append("\n")
    |> view.Tree

  [
    view.blank(),
    mini_map,
    room_view(room, observer),
  ]
  |> view.join("\n")
}

pub fn room_view(room: Room, observer: world.Mobile) -> View {
  let preamble =
    [color_room_title, room.name, color_reset, "\n  ", room.description, "\n"]
    |> string_tree.from_strings

  let exits =
    room.exits
    |> list.map(fn(exit) {
      case exit.door {
        Some(world.Door(state: world.Closed, ..)) ->
          ["+", world.direction_to_string(exit.keyword)]
          |> string_tree.from_strings

        Some(world.Door(state: world.Open, ..)) ->
          ["'", world.direction_to_string(exit.keyword)]
          |> string_tree.from_strings

        None ->
          world.direction_to_string(exit.keyword)
          |> string_tree.from_string
      }
    })
    |> string_tree.join(" ")
    |> string_tree.prepend("&189[Obvious Exits: &W")
    |> string_tree.append("&189]0;\n")

  let observer_id = observer.id
  let mobiles =
    room.characters
    // filter out observer
    |> list.filter(fn(character) {
      observer_id != character.id
      && !flag.affect_has(character.affects, flag.SuperInvisible)
    })
    |> list.map(fn(character) {
      [character.short, "\n"]
      |> string_tree.from_strings
    })
    |> string_tree.concat

  let items =
    list.filter_map(room.items, fn(item_instance) {
      case item_instance.item {
        world.Loaded(world.Item(short:, ..)) ->
          ["    ", short, "\n"]
          |> string_tree.from_strings
          |> Ok

        world.Loading(_) -> Error(Nil)
      }
    })
    |> string_tree.concat

  [preamble, exits, items, mobiles]
  |> list.filter(fn(tree) { !string_tree.is_empty(tree) })
  |> string_tree.concat
  |> view.Tree
}
