import gleam/option.{type Option, None, Some}
import lore/character/view.{type View}
import lore/world.{type Direction, type Mobile}

pub fn notify_arrive(character: Mobile, room_exit: Option(Direction)) -> View {
  let exit = case room_exit {
    Some(direction) -> direction
    None -> world.CustomExit("some unseen corner.")
  }

  case exit {
    world.CustomExit(custom_message) -> [
      character.name,
      " arrives from ",
      custom_message,
    ]
    _ -> [character.name, " arrives from the ", world.direction_to_string(exit)]
  }
  |> view.Leaves
}

pub fn notify_depart(character: Mobile, room_exit: Option(Direction)) -> View {
  case room_exit {
    Some(keyword) -> [
      character.name,
      " departs ",
      world.direction_to_string(keyword),
      ".",
    ]
    None -> [character.name, " seems to have gone missing!"]
  }
  |> view.Leaves
}

pub fn notify_spawn(character: Mobile) -> View {
  [character.name, " appears in a poof of smoke!"]
  |> view.Leaves
}

pub fn exit(room_exit: Option(Direction)) -> View {
  case room_exit {
    Some(keyword) ->
      ["You depart ", world.direction_to_string(keyword), "."]
      |> view.Leaves

    None -> "You slip through a crack in interstitial space!" |> view.Leaf
  }
}
