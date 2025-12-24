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
    use instance <- result.try(find_local_item(builder, item_keyword))
    case instance.was_touched {
      True -> {
        let names = response.system_tables(builder)
        janitor.item_cancel_clean_up(names.janitor, instance.id)
        instance
      }

      False -> world.ItemInstance(..instance, was_touched: True)
    }
    |> Ok
  }

  case result {
    Ok(instance) -> {
      let instance = world.ItemInstance(..instance, was_touched: True)

      builder
      |> response.item_delete(instance)
      |> response.broadcast(event.acting_character, ItemGetNotify(instance))
    }

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
