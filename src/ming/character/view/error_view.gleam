import gleam/string
import ming/character/view.{type View}
import ming/world.{type MoveError, type UnknownError}

pub fn move_error(error: MoveError) -> View {
  case error {
    world.Unknown(error) -> {
      let assert view.Leaf(s) = unknown_error(error)
      s
    }

    world.RoomLookupFailed(..) ->
      "So strange. It's as if that destination doesn't want to be found."

    world.CallFailed(..) ->
      "You feel a ripple of instability as the universe pushes back against you."

    world.CharacterLacksPermission -> "You lack permission to enter."

    world.RoomSetToPrivate -> "That room is private."

    world.ExitBlocked(direction) ->
      "The exit" <> string.inspect(direction) <> " is blocked."

    world.ArrivalFailed(..) ->
      "As you proceed across the threshold you suddenly stop as if the universe rejects you."
  }
  |> view.Leaf
}

pub fn unknown_error(error: UnknownError) -> View {
  case error {
    world.UnknownExit(direction:) ->
      "There is no exit" <> string.inspect(direction) <> " ."
  }
  |> view.Leaf
}
