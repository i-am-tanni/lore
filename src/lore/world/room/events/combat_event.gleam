import gleam/bool
import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{None, Some}
import gleam/result.{try}
import gleam/set
import lore/character/flag
import lore/world.{type Mobile, type StringId, NoTarget, Player}
import lore/world/event.{
  type CharacterMessage, type CharacterToRoomEvent, type Event,
}
import lore/world/room/response

type CombatRoundTemp {
  CombatRoundTemp(
    participants: Dict(StringId(world.Mobile), world.Mobile),
    commits: List(event.CombatPollData),
    continue: Bool,
  )
}

pub fn request(
  builder: response.Builder(CharacterMessage),
  event: Event(CharacterToRoomEvent, CharacterMessage),
  data: event.CombatRequestData,
) -> response.Builder(CharacterMessage) {
  let attacker = event.acting_character

  let result = {
    use victim <- try(find_local_character(builder, data.victim))
    use <- bool.guard(
      flag.affect_has(victim.affects, flag.GodMode),
      Error(world.GodMode),
    )
    use <- bool.guard(is_pvp(attacker, victim), Error(world.PvpForbidden))
    event.CombatPollData(
      attacker_id: event.acting_character.id,
      victim_id: victim.id,
      dam_roll: data.dam_roll,
    )
    |> Ok
  }

  let is_round_based = data.is_round_based
  let is_room_in_combat = response.is_in_combat(builder)
  case result {
    Ok(round_data) if is_round_based && !is_room_in_combat ->
      builder
      |> response.round_push(round_data)
      |> response.combat_commence(attacker)

    Ok(round_data) if is_round_based -> response.round_push(builder, round_data)

    Ok(combat_data) -> process_combat(builder, combat_data)

    Error(error) -> response.reply_character(builder, event.ActFailed(error))
  }
}

pub fn round_trigger(
  builder: response.Builder(event.RoomMessage),
  actions: List(event.CombatPollData),
) -> response.Builder(event.RoomMessage) {
  // filter participants
  let participants =
    actions
    |> list.flat_map(fn(action) { [action.attacker_id, action.victim_id] })
    |> set.from_list

  // Make sure participants are still in the room
  let world.Room(characters:, ..) = response.room(builder)
  let participants =
    list.filter_map(characters, fn(character) {
      case set.contains(participants, character.id) {
        True -> Ok(#(character.id, character))
        False -> Error(Nil)
      }
    })
    |> dict.from_list()

  // update participants and generate commits to broadcast
  let CombatRoundTemp(participants:, commits:, continue:) =
    CombatRoundTemp(participants:, commits: [], continue: False)
    |> list.fold(actions, _, round_process_action)

  // build response
  let builder = case !continue {
    True -> response.combat_end(builder)
    False -> builder
  }

  let result = {
    use acting_character_to_ignore <- try(list.first(characters))
    let round_event =
      event.CombatRound(participants:, commits: list.reverse(commits))

    // update characters list
    list.map(characters, fn(character) {
      case dict.get(participants, character.id) {
        Ok(update) -> update
        Error(Nil) -> character
      }
    })
    |> response.characters_put(builder, _)
    |> response.broadcast(acting_character_to_ignore, round_event)
    |> Ok
  }

  case result {
    Ok(builder) -> builder
    Error(_) -> builder
  }
}

pub fn process_combat(
  builder: response.Builder(CharacterMessage),
  data: event.CombatPollData,
) -> response.Builder(CharacterMessage) {
  let result = {
    let event.CombatPollData(victim_id:, attacker_id:, dam_roll:) = data

    // Make sure actors are still in the room
    use attacker <- try(find_local_character(
      builder,
      event.SearchId(attacker_id),
    ))
    use victim <- try(find_local_character(builder, event.SearchId(victim_id)))

    let #(victim, is_victim_alive) = case victim.hp - dam_roll {
      hp if hp > 0 && victim.fighting == world.NoTarget -> #(
        world.Mobile(..victim, hp:, fighting: world.Fighting(attacker.id)),
        True,
      )

      hp if hp > 0 -> #(world.Mobile(..victim, hp:), True)

      // ..else victim is dead
      hp -> #(world.Mobile(..victim, hp:, fighting: world.NoTarget), False)
    }

    let attacker_update = case attacker.fighting {
      world.NoTarget if is_victim_alive ->
        Some(world.Mobile(..attacker, fighting: world.Fighting(victim.id)))

      world.Fighting(_) if !is_victim_alive ->
        Some(world.Mobile(..attacker, fighting: world.NoTarget))

      _ -> None
    }

    let builder = case attacker_update {
      Some(update) -> response.character_update(builder, update)
      None -> builder
    }

    let attacker = case attacker_update {
      Some(update) -> update
      None -> attacker
    }

    let builder =
      event.CombatCommitData(victim:, attacker:, damage: dam_roll)
      |> event.CombatCommit
      |> response.broadcast(builder, attacker, _)
      |> response.character_update(victim)

    case is_victim_alive && !response.is_in_combat(builder) {
      True -> response.combat_commence(builder, attacker)
      False -> builder
    }
    |> Ok
  }

  case result {
    Ok(response) -> response
    Error(_) -> builder
  }
}

fn round_process_action(
  temp: CombatRoundTemp,
  action: event.CombatPollData,
) -> CombatRoundTemp {
  let CombatRoundTemp(participants:, commits:, continue:) = temp

  let result = {
    // find and update characters
    // confirm characters are alive
    let event.CombatPollData(victim_id:, attacker_id:, dam_roll:) = action
    use attacker <- try(dict.get(participants, attacker_id))
    use victim <- try(dict.get(participants, victim_id))
    use <- bool.guard(attacker.hp <= 0, Error(Nil))
    use <- bool.guard(flag.affect_has(victim.affects, flag.GodMode), Error(Nil))
    let victim = case victim.hp - dam_roll {
      hp if hp > 0 -> world.Mobile(..victim, hp:)
      hp -> world.Mobile(..victim, hp:, fighting: NoTarget)
    }

    let attacker = case attacker.fighting {
      world.Fighting(_) if victim.hp <= 0 ->
        Some(world.Mobile(..attacker, fighting: world.NoTarget))

      NoTarget if victim.hp > 0 ->
        Some(world.Mobile(..attacker, fighting: world.Fighting(victim_id)))

      _ -> None
    }

    let participants = case attacker {
      Some(update) -> dict.insert(participants, attacker_id, update)
      None -> participants
    }

    let participants = dict.insert(participants, victim_id, victim)

    // prepend commits
    let commits =
      event.CombatPollData(attacker_id:, victim_id:, dam_roll: dam_roll)
      |> list.prepend(commits, _)

    // Continue only if any victims have hp > 0
    let continue = continue || victim.hp > 0

    Ok(CombatRoundTemp(participants:, commits:, continue:))
  }

  case result {
    Ok(response) -> response
    Error(_) -> temp
  }
}

pub fn slay(
  builder: response.Builder(CharacterMessage),
  event: Event(CharacterToRoomEvent, CharacterMessage),
  victim: event.SearchTerm(Mobile),
) -> response.Builder(CharacterMessage) {
  let result = {
    use victim <- try(find_local_character(builder, victim))
    use <- bool.guard(
      flag.affect_has(victim.affects, flag.GodMode),
      Error(world.GodMode),
    )
    let damage = victim.hp_max * 6
    let victim = world.Mobile(..victim, hp: victim.hp - damage)
    let attacker = event.acting_character
    event.CombatCommitData(victim:, attacker:, damage:)
    |> event.CombatCommit
    |> response.broadcast(builder, attacker, _)
    |> response.character_update(victim)
    |> Ok
  }

  case result {
    Ok(update) -> update
    Error(error) -> response.reply_character(builder, event.ActFailed(error))
  }
}

fn is_pvp(attacker: Mobile, victim: Mobile) -> Bool {
  case attacker.template_id, victim.template_id {
    Player(_), Player(_) -> True
    _, _ -> False
  }
}

fn find_local_character(
  builder: response.Builder(a),
  search_term: event.SearchTerm(Mobile),
) -> Result(Mobile, world.ErrorRoomRequest) {
  case search_term {
    event.Keyword(term) ->
      response.find_local_character(builder, fn(character) {
        list.any(character.keywords, fn(keyword) { term == keyword })
      })

    event.SearchId(id) ->
      response.find_local_character(builder, fn(character) {
        id == character.id
      })
  }
}
