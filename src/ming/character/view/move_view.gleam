import gleam/option.{type Option, None, Some}
import gleam/string
import ming/character/view.{type View}
import ming/world.{type Mobile, type RoomExit}

pub fn notify_arrive(character: Mobile, room_exit: Option(RoomExit)) -> View {
  case room_exit {
    Some(room_exit) -> [
      character.name,
      " arrives from the ",
      string.inspect(room_exit.keyword),
      ".",
    ]
    None -> [character.name, " arrives from some unseen corner."]
  }
  |> view.Leaves
}

pub fn notify_depart(character: Mobile, room_exit: Option(RoomExit)) -> View {
  case room_exit {
    Some(exit) -> [
      character.name,
      " departs ",
      string.inspect(exit.keyword),
      ".",
    ]
    None -> [character.name, " seems to have gone missing!"]
  }
  |> view.Leaves
}

pub fn exit(room_exit: Option(RoomExit)) -> View {
  case room_exit {
    Some(exit) ->
      ["You depart ", string.inspect(exit.keyword), "."]
      |> view.Leaves
    None -> "You slip through a crack in interstitial space!" |> view.Leaf
  }
}
