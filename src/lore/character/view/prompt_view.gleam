import gleam/int
import lore/character/view.{type View}
import lore/world

type VitalsPrint {
  VitalsPrint(hp: String, hp_max: String)
}

pub fn prompt(character: world.MobileInternal) -> View {
  let world.MobileInternal(hp:, hp_max:, ..) = character
  let vitals = VitalsPrint(hp: int.to_string(hp), hp_max: int.to_string(hp_max))

  ["<&R", vitals.hp, "/", vitals.hp_max, "hp0;> "]
  |> view.Leaves
}
