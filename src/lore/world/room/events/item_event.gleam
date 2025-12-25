import gleam/result
import gleam/time/duration
import lore/world
import lore/world/event.{
  type CharacterMessage, type CharacterToRoomEvent, type Event, ItemDropNotify,
  ItemGetNotify,
}
import lore/world/room/janitor
import lore/world/room/response

pub fn get(
  builder: response.Builder(CharacterMessage),
  event: Event(CharacterToRoomEvent, CharacterMessage),
  item_keyword: String,
) -> response.Builder(CharacterMessage) {
  let result = {
    use item_instance <- result.try(find_local_item(builder, item_keyword))
    case item_instance.was_touched {
      // If item instance was previously touched by a mobile
      // then it was dropped and thus scheduled for clean up. Cancel that.
      True -> {
        let names = response.system_tables(builder)
        janitor.item_cancel_clean_up(names.janitor, item_instance.id)
        item_instance
      }
      // ..else mark it as touched so we can schedule a clean up if it gets
      // dropped
      False -> world.ItemInstance(..item_instance, was_touched: True)
    }
    |> Ok
  }

  case result {
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
  let names = response.system_tables(builder)
  let world.Room(id: room_id, ..) = response.room(builder)

  janitor.item_schedule_clean_up(
    names.janitor,
    what: item_instance.id,
    at: room_id,
    in: duration.minutes(5),
  )

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
