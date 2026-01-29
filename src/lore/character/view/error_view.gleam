import gleam/int
import lore/character/view.{type View}
import lore/world

pub fn parse_error() -> View {
  "huh?"
  |> view.Leaf
}

pub fn render_error(error: String) -> View {
  view.Leaf(error)
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

    world.GodMode -> "You are forbidden to attack an immortal" |> view.Leaf
  }
}

pub fn item_error(err: world.ErrorItem) -> View {
  case err {
    world.UnknownItem(search_term:, verb:) -> [
      "You are not ",
      verb,
      " anything that matches ",
      search_term,
      ".",
    ]
    world.CannotBeWorn(item:) -> [item.name, " cannot be worn."]
    world.CannotWield(item:) -> ["You cannot be wield ", item.name]
    world.WearSlotFull(wear_slot:, item:) -> [
      "You must remove ",
      item.name,
      " from your ",
      wear_slot_to_string(wear_slot),
      " to wear that.",
    ]
    world.WearSlotMissing(wear_slot:) -> [
      "You lack the ",
      wear_slot_to_string(wear_slot),
      " to wear that.",
    ]
    world.InvalidItemId(item_id: world.Id(item_id)) -> [
      "Item id ",
      int.to_string(item_id),
      " is invalid.",
    ]
  }
  |> view.Leaves
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

pub fn already_fighting() {
  "You are fighting for your life!" |> view.Leaf
}

pub fn user_not_found(name: String) -> View {
  ["User ", name, " not found."]
  |> view.Leaves
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

fn wear_slot_to_string(wear_slot: world.WearSlot) -> String {
  case wear_slot {
    world.Arms -> "arms"
    world.CannotWear -> "[invalid wear slot]"
  }
}
