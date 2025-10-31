import lore/world
import lore/world/event.{
  type CharacterMessage, type CharacterToRoomEvent, type Event, ItemDropNotify,
  ItemGetNotify,
}
import lore/world/room/response

pub fn get(
  builder: response.Builder(CharacterMessage),
  event: Event(CharacterToRoomEvent, CharacterMessage),
  item_keyword: String,
) -> response.Builder(CharacterMessage) {
  case find_local_item(builder, item_keyword) {
    Ok(instance) ->
      builder
      |> response.item_delete(instance)
      |> response.broadcast(event.acting_character, ItemGetNotify(instance))

    Error(error) -> response.reply_character(builder, event.ActFailed(error))
  }
}

pub fn drop(
  builder: response.Builder(CharacterMessage),
  event: Event(CharacterToRoomEvent, CharacterMessage),
  item_instance: world.ItemInstance,
) -> response.Builder(CharacterMessage) {
  builder
  |> response.item_insert(item_instance)
  |> response.broadcast(event.acting_character, ItemDropNotify(item_instance))
}

fn find_local_item(
  builder: response.Builder(CharacterMessage),
  search_term: String,
) -> Result(world.ItemInstance, world.ErrorRoomRequest) {
  response.find_local_item(builder, search_term)
}
