import lore/character/view.{type View}
import lore/world
import lore/world/event

pub fn notify(
  self: world.MobileInternal,
  acting_character: world.Mobile,
  data: event.DoorNotifyData,
) -> View {
  let direction = world.direction_to_string(data.exit.keyword)

  case view.perspective_simple(self, acting_character) {
    view.Self -> [
      "You ",
      door_verb(view.Self, data.update),
      " the ",
      direction,
      " door.",
    ]

    view.Witness if data.is_subject_observable -> [
      acting_character.name,
      " ",
      door_verb(view.Witness, data.update),
      " the door ",
      direction,
      ".",
    ]

    view.Witness -> [
      "The ",
      direction,
      " door ",
      door_verb(view.Self, data.update),
      ".",
    ]
  }
  |> view.Leaves
}

fn door_verb(
  perspective: view.PerspectiveSimple,
  access: world.AccessState,
) -> String {
  case perspective, access {
    view.Self, world.Open -> "open"
    view.Witness, world.Open -> "opens"
    view.Self, world.Closed -> "close"
    view.Witness, world.Closed -> "closes"
  }
}
