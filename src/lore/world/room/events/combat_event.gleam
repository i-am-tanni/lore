import gleam/bool
import gleam/list
import gleam/result.{try}
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
    let event.CombatRequestData(victim:, dam_roll:) = data
    let attacker_id = event.acting_character.id
    use attacker <- try(find_local_character(
      builder,
      event.SearchId(attacker_id),
    ))
    use victim <- try(find_local_character(builder, victim))
    use <- bool.guard(is_pvp(attacker, victim), Error(world.PvpForbidden))

    let builder = case !attacker.is_in_combat {
      True ->
        world.Mobile(..attacker, is_in_combat: True)
        |> response.character_update(builder, _)

      False -> builder
    }

    let victim = world.Mobile(..victim, hp: victim.hp - dam_roll)

    event.CombatCommitData(victim:, damage: dam_roll)
    |> event.CombatCommit
    |> response.broadcast(builder, attacker, _)
    |> response.character_update(attacker)
    |> response.character_update(victim)
    |> Ok
  }

  case result {
    Ok(response) -> response
    Error(error) ->
      response.reply_character(builder, event, event.ActFailed(error))
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
