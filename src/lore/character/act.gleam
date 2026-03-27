import lore/world
import lore/world/event.{type Action, Action}
import lore/world/keyword

const min_delay = 500

pub fn move(direction: world.Direction) -> Action {
  Action(
    event: event.MoveRequest(direction),
    id: world.generate_id(),
    condition: no_conditions,
    priority: event.Medium,
    delay: min_delay,
  )
}

pub fn toggle_door(data: event.DoorToggleData) -> Action {
  Action(
    event: event.DoorToggle(data),
    id: world.generate_id(),
    condition: no_conditions,
    priority: event.Medium,
    delay: min_delay,
  )
}

pub fn communicate(data: event.RoomCommunicationData) -> Action {
  Action(
    event: event.RoomCommunication(data),
    id: world.generate_id(),
    condition: no_conditions,
    priority: event.Medium,
    delay: min_delay,
  )
}

pub fn item_get(query: keyword.SpecifiedSearch) -> Action {
  Action(
    event: event.ItemGet(query),
    id: world.generate_id(),
    condition: no_conditions,
    priority: event.Medium,
    delay: min_delay,
  )
}

pub fn item_get_all() -> Action {
  Action(
    event: event.ItemGetAll,
    id: world.generate_id(),
    condition: no_conditions,
    priority: event.Medium,
    delay: min_delay,
  )
}

pub fn item_drop(item_instance: world.ItemInstance) -> Action {
  Action(
    event: event.ItemDrop(item_instance),
    id: world.generate_id(),
    condition: no_conditions,
    priority: event.Medium,
    delay: min_delay,
  )
}

pub fn kill(data: event.CombatRequestData) -> Action {
  Action(
    event: event.CombatRequest(data),
    id: world.generate_id(),
    condition: no_conditions,
    priority: event.Medium,
    delay: min_delay,
  )
}

fn no_conditions(
  character: world.MobileInternal,
) -> Result(world.MobileInternal, String) {
  Ok(character)
}
