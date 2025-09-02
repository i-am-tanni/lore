import gleam/int
import gleam/list
import gleam/string_tree
import lore/character/users
import lore/character/view.{type View}
import lore/world

const color_bwhite = "&W"

const color_reset = "0;"

pub fn quit() -> View {
  view.Leaf("See you next time!~")
}

pub fn name(character: world.Mobile) -> String {
  character.name
}

pub fn who_list(users: List(users.User)) -> View {
  let num_users = list.length(users)
  let preamble =
    [
      "There are currently ",
      color_bwhite,
      int.to_string(num_users),
      color_reset,
      " users online:\n",
    ]
    |> string_tree.from_strings

  list.fold(users, preamble, fn(acc, user) {
    ["    ", user.name, "\n"]
    |> string_tree.from_strings
    |> string_tree.append_tree(acc, _)
  })
  |> view.Tree
}

pub fn look_at(character: world.MobileInternal) -> View {
  character.name
  |> view.Leaf
}
