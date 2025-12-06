import gleam/list
import gleam/result.{try_recover}
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
  ExtraDesc(world.ExtraDesc)
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
  let room = response.room(builder)

  let result = {
    use _ <- try_recover(
      find_local_item(room, search_term)
      |> result.map(Item),
    )
    use _ <- try_recover(
      find_local_character(room, search_term)
      |> result.map(Mobile),
    )
    find_local_xdesc(room, search_term)
    |> result.map(ExtraDesc)
  }

  case result {
    Ok(Item(item_match)) ->
      response.reply_character(builder, event.ItemInspect(item_match))

    Ok(Mobile(mobile_match)) -> {
      response.character_event(
        builder,
        event.MobileInspectRequest(event.from),
        event.acting_character,
        mobile_match.id,
      )
    }

    Ok(ExtraDesc(xdesc_match)) -> {
      response.renderln(builder, view.text(xdesc_match.text))
    }

    Error(_) ->
      response.reply_character(
        builder,
        event.ActFailed(world.NotFound(search_term)),
      )
  }
}

fn find_local_item(
  room: world.Room,
  term: String,
) -> Result(world.ItemInstance, Nil) {
  list.find(room.items, fn(item) {
    list.any(item.keywords, fn(keyword) { term == keyword })
  })
}

fn find_local_character(room: world.Room, term: String) -> Result(Mobile, Nil) {
  list.find(room.characters, fn(character) {
    list.any(character.keywords, fn(keyword) { term == keyword })
  })
}

fn find_local_xdesc(
  room: world.Room,
  term: String,
) -> Result(world.ExtraDesc, Nil) {
  list.find(room.xdescs, fn(xdesc) {
    list.any([xdesc.short, ..xdesc.keywords], fn(keyword) { term == keyword })
  })
}
