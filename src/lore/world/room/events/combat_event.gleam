import gleam/bool
import gleam/list
import gleam/result.{try}
import gleam/set
import lore/world.{type Mobile, Player}
import lore/world/event.{
  type CharacterMessage, type CharacterToRoomEvent, type Event,
}
import lore/world/room/response

pub fn request(
  builder: response.Builder(CharacterMessage),
  event: Event(CharacterToRoomEvent, CharacterMessage),
  data: event.CombatRequestData,
) -> response.Builder(CharacterMessage) {
  let result = {
    use victim <- try(find_local_character(builder, data.victim))

    use <- bool.guard(
      is_pvp(event.acting_character, victim),
      Error(world.PvpForbidden),
    )
    world.CombatPollData(
      attacker_id: event.acting_character.id,
      victim_id: victim.id,
      dam_roll: data.dam_roll,
    )
    |> Ok
  }

  case result {
    Ok(round_data) if data.is_round_based ->
      response.round_push(builder, round_data)

    Ok(round_data) -> process_combat(builder, round_data)

    Error(error) -> response.reply_character(builder, event.ActFailed(error))
  }
}

pub fn round_trigger(
  builder: response.Builder(CharacterMessage),
  actions: List(world.CombatPollData),
) -> response.Builder(CharacterMessage) {
  // filter participants
  let participants =
    actions
    |> list.fold(set.new(), fn(acc, action) {
      acc
      |> set.insert(action.attacker_id)
      |> set.insert(action.victim_id)
    })

  // Make sure participants are still in the room
  let world.Room(characters:, ..) = response.room(builder)
  let participants =
    list.filter(characters, fn(character) {
      set.contains(participants, character.id)
    })

  // update participants and get commits to broadcast
  let #(updated_participants, commits) =
    list.fold(actions, #(participants, list.new()), fn(acc, action) {
      let #(participants, commits) = acc
      process_round_action(action, participants, commits)
    })

  use <- bool.guard(commits == [] || participants == [], builder)
  let assert [world.CombatPollData(attacker_id:, ..), _] = commits
  let assert Ok(acting_character_to_ignore) =
    list.find(participants, fn(mobile) { mobile.id == attacker_id })

  let round_event =
    event.CombatRound(
      participants: updated_participants,
      commits: list.reverse(commits),
    )

  // update characters list
  list.fold(updated_participants, characters, update_character_in_list)
  |> response.characters_put(builder, _)
  |> response.broadcast(acting_character_to_ignore, round_event)
}

pub fn process_combat(
  builder: response.Builder(CharacterMessage),
  data: world.CombatPollData,
) -> response.Builder(CharacterMessage) {
  let result = {
    let world.CombatPollData(victim_id:, attacker_id:, dam_roll:) = data

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

pub fn process_round_action(
  data: world.CombatPollData,
  participants: List(world.Mobile),
  commits: List(world.CombatPollData),
) -> #(List(world.Mobile), List(world.CombatPollData)) {
  let result = {
    // find characters
    let world.CombatPollData(victim_id:, attacker_id:, dam_roll:) = data
    use attacker <- try(find_character(
      participants,
      event.SearchId(attacker_id),
    ))
    use victim <- try(find_character(participants, event.SearchId(victim_id)))

    // update characters
    let updates = case !attacker.is_in_combat {
      True -> [world.Mobile(..attacker, is_in_combat: True)]
      False -> []
    }
    let updates = [world.Mobile(..victim, hp: victim.hp - dam_roll), ..updates]
    let participants =
      list.fold(updates, participants, update_character_in_list)

    // prepend commits
    let commits =
      world.CombatPollData(attacker_id:, victim_id:, dam_roll: dam_roll)
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

fn find_character(
  characters: List(world.Mobile),
  search_term: event.SearchTerm(Mobile),
) -> Result(Mobile, Nil) {
  case search_term {
    event.Keyword(term) ->
      list.find(characters, fn(character) {
        list.any(character.keywords, fn(keyword) { term == keyword })
      })

    event.SearchId(id) ->
      list.find(characters, fn(character) { id == character.id })
  }
}

fn update_character_in_list(
  list: List(world.Mobile),
  update: world.Mobile,
) -> List(world.Mobile) {
  list.map(list, fn(member) {
    case member.id == update.id {
      True -> update
      False -> member
    }
  })
}
