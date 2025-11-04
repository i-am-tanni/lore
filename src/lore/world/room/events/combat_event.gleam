import gleam/bool
import gleam/dict.{type Dict}
import gleam/list
import gleam/result.{try}
import gleam/set
import lore/world.{type Mobile, type StringId, Player}
import lore/world/event.{
  type CharacterMessage, type CharacterToRoomEvent, type Event,
}
import lore/world/room/response

pub fn request(
  builder: response.Builder(CharacterMessage),
  event: Event(CharacterToRoomEvent, CharacterMessage),
  data: event.CombatRequestData,
) -> response.Builder(CharacterMessage) {
  let attacker = event.acting_character
  let result = {
    use victim <- try(find_local_character(builder, data.victim))

    use <- bool.guard(is_pvp(attacker, victim), Error(world.PvpForbidden))
    event.CombatPollData(
      attacker_id: event.acting_character.id,
      victim_id: victim.id,
      dam_roll: data.dam_roll,
    )
    |> Ok
  }

  let builder = case result {
    Ok(round_data) if data.is_round_based ->
      response.round_push(builder, round_data)

    Ok(combat_data) -> process_combat(builder, combat_data)

    Error(error) -> response.reply_character(builder, event.ActFailed(error))
  }

  case !response.is_in_combat(builder) {
    True -> response.combat_commence(builder, attacker)
    False -> builder
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
  let #(participants, commits) =
    list.fold(actions, #(participants, list.new()), fn(acc, action) {
      let #(participants, commits) = acc
      round_process_action(action, participants, commits)
    })

  // build response
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

    let builder = case !attacker.is_in_combat {
      True ->
        world.Mobile(..attacker, is_in_combat: True)
        |> response.character_update(builder, _)

      False -> builder
    }

    let victim = world.Mobile(..victim, hp: victim.hp - dam_roll)

    event.CombatCommitData(victim:, attacker:, damage: dam_roll)
    |> event.CombatCommit
    |> response.broadcast(builder, attacker, _)
    |> response.character_update(victim)
    |> Ok
  }

  case result {
    Ok(response) -> response
    Error(_) -> builder
  }
}

pub fn round_process_action(
  action: event.CombatPollData,
  participants: Dict(StringId(Mobile), Mobile),
  commits: List(event.CombatPollData),
) -> #(Dict(StringId(Mobile), Mobile), List(event.CombatPollData)) {
  let result = {
    // find and update characters
    let event.CombatPollData(victim_id:, attacker_id:, dam_roll:) = action
    use attacker <- try(dict.get(participants, attacker_id))
    use victim <- try(dict.get(participants, victim_id))
    let participants = case !attacker.is_in_combat {
      True ->
        world.Mobile(..attacker, is_in_combat: True)
        |> dict.insert(participants, attacker_id, _)

      False -> participants
    }

    let participants =
      world.Mobile(..victim, hp: victim.hp - dam_roll)
      |> dict.insert(participants, victim_id, _)

    // prepend commits
    let commits =
      event.CombatPollData(attacker_id:, victim_id:, dam_roll: dam_roll)
      |> list.prepend(commits, _)

    #(participants, commits)
    |> Ok
  }

  case result {
    Ok(response) -> response
    Error(_) -> #(participants, commits)
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
