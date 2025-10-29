import gleam/list
import gleam/result
import lore/character/view
import lore/character/view/look_view
import lore/world.{type Mobile}
import lore/world/event.{type CharacterMessage, type Event}
import lore/world/items
import lore/world/room/response
import lore/world/system_tables

type Found {
  Item(world.ItemInstance)
  Mobile(world.Mobile)
}

pub fn room_look(
  builder: response.Builder(CharacterMessage),
  event: Event(event.CharacterToRoomEvent, CharacterMessage),
) -> response.Builder(CharacterMessage) {
  let system_tables.Lookup(items: items_table, ..) =
    response.system_tables(builder)
  let room = response.room(builder)

  // Load Items
  let room = {
    let loaded = items.load_instances(items_table, room.items)
    world.Room(..room, items: loaded)
  }

  builder
  |> response.renderln(view.blank())
  |> response.renderln(look_view.mini_map(response.mini_map(builder)))
  |> response.render(look_view.room(room, event.acting_character))
}

pub fn look_at(
  builder: response.Builder(CharacterMessage),
  event: Event(event.CharacterToRoomEvent, CharacterMessage),
  search_term: String,
) -> response.Builder(CharacterMessage) {
  let result = {
    use _ <- result.try_recover(
      response.find_local_item(builder, search_term) |> result.map(Item),
    )
    find_local_character(builder, search_term)
    |> result.map(Mobile)
  }

  case result {
    Ok(Item(item_match)) ->
      response.reply_character(builder, event, event.ItemInspect(item_match))

    Ok(Mobile(mobile_match)) -> {
      response.character_event(
        builder,
        event.MobileInspectRequest(event.from),
        event.acting_character,
        mobile_match.id,
      )
    }

    Error(_) ->
      response.reply_character(
        builder,
        event,
        event.ActFailed(world.NotFound(search_term)),
      )
  }
}

fn find_local_character(
  builder: response.Builder(a),
  term: String,
) -> Result(Mobile, world.ErrorRoomRequest) {
  response.find_local_character(builder, fn(character) {
    list.any(character.keywords, fn(keyword) { term == keyword })
  })
}
