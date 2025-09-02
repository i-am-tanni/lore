import lore/world
import lore/world/event.{type Action, Action}

pub fn move(direction: world.Direction) -> Action {
  Action(
    event: event.MoveRequest(direction),
    id: world.generate_id(),
    condition: no_conditions,
    priority: event.Medium,
    delay: 500,
  )
}

pub fn toggle_door(data: event.DoorToggleData) -> Action {
  Action(
    event: event.DoorToggle(data),
    id: world.generate_id(),
    condition: no_conditions,
    priority: event.Medium,
    delay: 500,
  )
}

pub fn communicate(data: event.RoomCommunicationData) -> Action {
  Action(
    event: event.RoomCommunication(data),
    id: world.generate_id(),
    condition: no_conditions,
    priority: event.Medium,
    delay: 500,
  )
}

pub fn item_get(keyword: String) -> Action {
  Action(
    event: event.ItemGet(keyword),
    id: world.generate_id(),
    condition: no_conditions,
    priority: event.Medium,
    delay: 500,
  )
}

pub fn item_drop(item_instance: world.ItemInstance) -> Action {
  Action(
    event: event.ItemDrop(item_instance),
    id: world.generate_id(),
    condition: no_conditions,
    priority: event.Medium,
    delay: 500,
  )
}

fn no_conditions(
  character: world.MobileInternal,
) -> Result(world.MobileInternal, String) {
  Ok(character)
}
