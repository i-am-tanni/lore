import lore/character/view.{type View}
import lore/world

pub fn parse_error(_) -> View {
  "huh?"
  |> view.Leaf
}

pub fn room_request_error(error: world.ErrorRoomRequest) -> View {
  case error {
    world.UnknownExit(direction:) ->
      ["There is no exit ", direction_to_string(direction), "."]
      |> view.Leaves

    world.CharacterLookupFailed ->
      "That character doesn't seem to be here."
      |> view.Leaf

    world.ItemLookupFailed(keyword:) ->
      ["Unable to find item: ", keyword]
      |> view.Leaves

    world.RoomLookupFailed(..) ->
      "So strange. It's as if that destination doesn't want to be found."
      |> view.Leaf

    world.MoveErr(move_err) -> move_error(move_err)

    world.DoorErr(door_err) -> door_error(door_err)

    world.NotFound(keyword) ->
      ["Unable to find '", keyword, "'."] |> view.Leaves

    world.PvpForbidden -> "You cannot attack other players." |> view.Leaf
  }
}

pub fn not_carrying_error() -> View {
  "You aren't carrying that." |> view.Leaf
}

fn move_error(error: world.ErrorMove) -> View {
  case error {
    world.Unauthorized -> "You lack the permissions to enter." |> view.Leaf
  }
}

fn door_error(error: world.ErrorDoor) -> View {
  case error {
    world.DoorLocked -> "The door is closed and locked." |> view.Leaf
    world.NoChangeNeeded(state) ->
      ["The door is already ", access_to_string(state), "."] |> view.Leaves
    world.MissingDoor(direction) ->
      ["There is no door ", direction_to_string(direction), "."] |> view.Leaves
    world.DoorClosed -> "The door is closed." |> view.Leaf
  }
}

pub fn cannot_target_self() {
  "That would be unwise." |> view.Leaf
}

fn direction_to_string(direction: world.Direction) -> String {
  case direction {
    world.North -> "north"
    world.South -> "south"
    world.East -> "east"
    world.West -> "west"
    world.Up -> "up"
    world.Down -> "down"
    world.CustomExit(custom) -> custom
  }
}

fn access_to_string(access: world.AccessState) -> String {
  case access {
    world.Open -> "open"
    world.Closed -> "closed"
  }
}
