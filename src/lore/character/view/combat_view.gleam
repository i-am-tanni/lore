import gleam/int
import gleam/list
import gleam/result.{try}
import gleam/string_tree
import lore/character/view.{type View}
import lore/character/view/character_view
import lore/world
import lore/world/event

type Perspective {
  Attacker
  Victim
  Witness
}

pub fn notify(self: world.MobileInternal, data: event.CombatCommitData) -> View {
  let event.CombatCommitData(victim:, attacker:, damage:) = data
  let victim_hp_max = victim.hp_max

  case perspective(self, attacker, data.victim) {
    Attacker -> [
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

pub fn round_report(
  self: world.MobileInternal,
  participants: List(world.Mobile),
  commits: List(world.CombatPollData),
) -> View {
  list.filter_map(commits, fn(commit) {
    let world.CombatPollData(attacker_id:, victim_id:, dam_roll:) = commit
    use attacker <- try(list.find(participants, id_match(_, attacker_id)))
    use victim <- try(list.find(participants, id_match(_, victim_id)))
    let commit = event.CombatCommitData(attacker:, victim:, damage: dam_roll)
    Ok(notify(self, commit))
  })
  |> view.join("\n")
}

pub fn round_summary(
  self: world.MobileInternal,
  participants: List(world.Mobile),
) -> View {
  let self_id = self.id
  let participants = list.filter(participants, id_match(_, self_id))
  let prelude =
    [
      "You ",
      health_feedback_1p(self),
    ]
    |> string_tree.from_strings

  let rest =
    list.map(participants, fn(participant) {
      [
        character_view.name(participant),
        " ",
        health_feedback_3p(participant),
      ]
      |> string_tree.from_strings()
    })

  string_tree.join([prelude, ..rest], "\n")
  |> view.Tree
}

fn perspective(
  self: world.MobileInternal,
  acting_character: world.Mobile,
  victim: world.Mobile,
) -> Perspective {
  case self.id {
    self if self == acting_character.id -> Attacker
    self if self == victim.id -> Victim
    _ -> Witness
  }
}

fn id_match(a: world.Mobile, id: world.StringId(world.Mobile)) -> Bool {
  a.id == id
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

fn health_feedback_1p(mobile: world.MobileInternal) -> String {
  let hp_percent = 100 * mobile.hp / mobile.hp_max
  case hp_percent {
    _ if hp_percent >= 100 -> "are in excellent condition."
    _ if hp_percent >= 90 -> "have a few scratches."
    _ if hp_percent >= 75 -> "have some small wounds and bruises."
    _ if hp_percent >= 50 -> "have quite a few wounds."
    _ if hp_percent >= 30 -> "have some big nasty wounds and scratches."
    _ if hp_percent >= 15 -> "look pretty hurt."
    _ if hp_percent >= 0 -> "are in awful condition."
    _ -> "are bleeding to death."
  }
}

fn health_feedback_3p(mobile: world.Mobile) -> String {
  let hp_percent = 100 * mobile.hp / mobile.hp_max
  case hp_percent {
    _ if hp_percent >= 100 -> "is in excellent condition."
    _ if hp_percent >= 90 -> "has a few scratches."
    _ if hp_percent >= 75 -> "has some small wounds and bruises."
    _ if hp_percent >= 50 -> "has quite a few wounds."
    _ if hp_percent >= 30 -> "has some big nasty wounds and scratches."
    _ if hp_percent >= 15 -> "looks pretty hurt."
    _ if hp_percent >= 0 -> "is in awful condition."
    _ -> "is bleeding to death."
  }
}
