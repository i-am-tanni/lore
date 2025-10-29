import gleam/int
import lore/character/view.{type View}
import lore/character/view/character_view
import lore/world
import lore/world/event

type Perspective {
  Self
  Victim
  Witness
}

pub fn notify(
  self: world.MobileInternal,
  attacker: world.Mobile,
  data: event.CombatCommitData,
) -> View {
  let event.CombatCommitData(victim:, damage:) = data
  let victim_hp_max = victim.hp_max

  case perspective(self, attacker, data.victim) {
    Self -> [
      "Your strike ",
      damage_feedback(damage, victim_hp_max),
      " ",
      character_view.name(victim),
      "! (",
      int.to_string(damage),
      ")",
    ]

    Victim -> [
      character_view.name(attacker),
      "'s strike ",
      damage_feedback(damage, victim_hp_max),
      " you!",
    ]

    Witness -> [
      character_view.name(attacker),
      " strikes ",
      character_view.name(victim),
      "!",
    ]
  }
  |> view.Leaves
}

fn perspective(
  self: world.MobileInternal,
  acting_character: world.Mobile,
  victim: world.Mobile,
) -> Perspective {
  case self.id {
    self if self == acting_character.id -> Self
    self if self == victim.id -> Victim
    _ -> Witness
  }
}

fn damage_feedback(damage: Int, victim_hp_max: Int) -> String {
  let dam_percent = 100 * damage / victim_hp_max
  case dam_percent {
    _ if dam_percent <= 0 -> "misses"
    _ if dam_percent <= 1 -> "tickles"
    _ if dam_percent <= 2 -> "nicks"
    _ if dam_percent <= 3 -> "scuffs"
    _ if dam_percent <= 4 -> "scrapes"
    _ if dam_percent <= 5 -> "scratches"
    _ if dam_percent <= 10 -> "grazes"
    _ if dam_percent <= 15 -> "injures"
    _ if dam_percent <= 20 -> "wounds"
    _ if dam_percent <= 25 -> "mauls"
    _ if dam_percent <= 30 -> "maims"
    _ if dam_percent <= 35 -> "mangles"
    _ if dam_percent <= 40 -> "mutilates"
    _ if dam_percent <= 45 -> "wrecks"
    _ if dam_percent <= 50 -> "DESTROYS"
    _ if dam_percent <= 55 -> "RAVAGES"
    _ if dam_percent <= 60 -> "TRAUMATIZES"
    _ if dam_percent <= 65 -> "CRIPPLES"
    _ if dam_percent <= 70 -> "MASSACRES"
    _ if dam_percent <= 75 -> "DEMOLISHES"
    _ if dam_percent <= 80 -> "DEVASTATES"
    _ if dam_percent <= 85 -> "PULVERIZES"
    _ if dam_percent <= 90 -> "OBLITERATES"
    _ if dam_percent <= 95 -> "ANNHILATES"
    _ if dam_percent <= 100 -> "ERADICATES"
    _ if dam_percent <= 200 -> "SLAUGHTERS"
    _ if dam_percent <= 300 -> "LIQUIFIES"
    _ if dam_percent <= 400 -> "VAPORIZES"
    _ if dam_percent <= 500 -> "ATOMIZES"
    _ -> "does UNSPEAKABLE things to"
  }
}
