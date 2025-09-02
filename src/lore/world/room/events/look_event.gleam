import gleam/erlang/process
import gleam/list
import gleam/result
import lore/character/view
import lore/character/view/look_view
import lore/character/view/prompt_view
import lore/world
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
    let loaded =
      list.filter_map(room.items, load_item_into_instance(items_table, _))
    world.Room(..room, items: loaded)
  }

  builder
  |> response.renderln(view.blank())
  |> response.renderln(look_view.mini_map(response.mini_map(builder)))
  |> response.renderln(look_view.room(room, event.acting_character))
  |> response.render(prompt_view.prompt())
}

pub fn look_at(
  builder: response.Builder(CharacterMessage),
  event: Event(event.CharacterToRoomEvent, CharacterMessage),
  search_keyword: String,
) -> response.Builder(CharacterMessage) {
  let result = {
    use _ <- result.try_recover(
      response.find_local_item(builder, search_keyword) |> result.map(Item),
    )
    response.find_local_character(builder, search_keyword)
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
        event.ActFailed(world.NotFound(search_keyword)),
      )
  }
}

fn load_item_into_instance(
  items_table: process.Name(items.Message),
  item_instance: world.ItemInstance,
) -> Result(world.ItemInstance, Nil) {
  case item_instance.item {
    world.Loading(id) -> {
      use item <- result.try(items.load(items_table, id))
      Ok(world.ItemInstance(..item_instance, item: world.Loaded(item)))
    }
    world.Loaded(_) -> Ok(item_instance)
  }
}
