import gleam/bool
import gleam/dict
import gleam/list
import gleam/result
import lore/character/conn.{
  type Action, type Conn, Action, External, Internal, Medium,
}
import lore/character/view/render
import lore/server/my_dict
import lore/world
import lore/world/event
import lore/world/items
import lore/world/keyword
import lore/world/named_actors

const min_delay = 500

pub fn move(direction: world.Direction) -> Action {
  Action(
    event: External(event.MoveRequest(direction)),
    id: world.generate_id(),
    condition: no_conditions,
    priority: Medium,
    delay: min_delay,
  )
}

pub fn toggle_door(data: event.DoorToggleData) -> Action {
  Action(
    event: External(event.DoorToggle(data)),
    id: world.generate_id(),
    condition: no_conditions,
    priority: Medium,
    delay: min_delay,
  )
}

pub fn communicate(data: event.RoomCommunicationData) -> Action {
  Action(
    event: External(event.RoomCommunication(data)),
    id: world.generate_id(),
    condition: no_conditions,
    priority: Medium,
    delay: min_delay,
  )
}

pub fn item_get(query: keyword.SpecifiedSearch) -> Action {
  Action(
    event: External(event.ItemGet(query)),
    id: world.generate_id(),
    condition: no_conditions,
    priority: Medium,
    delay: min_delay,
  )
}

pub fn item_get_all() -> Action {
  Action(
    event: External(event.ItemGetAll),
    id: world.generate_id(),
    condition: no_conditions,
    priority: Medium,
    delay: min_delay,
  )
}

pub fn item_drop(item_instance: world.ItemInstance) -> Action {
  Action(
    event: External(event.ItemDrop(item_instance)),
    id: world.generate_id(),
    condition: no_conditions,
    priority: Medium,
    delay: min_delay,
  )
}

pub fn kill(data: event.CombatRequestData) -> Action {
  Action(
    event: External(event.CombatRequest(data)),
    id: world.generate_id(),
    condition: no_conditions,
    priority: Medium,
    delay: min_delay,
  )
}

pub fn remove_item(search_term: String) -> Action {
  Action(
    event: Internal(do_remove_item(_, search_term)),
    id: world.generate_id(),
    condition: no_conditions,
    priority: Medium,
    delay: min_delay,
  )
}

pub fn wear_item(search_term: String) -> Action {
  Action(
    event: Internal(do_wear_item(_, search_term)),
    id: world.generate_id(),
    condition: no_conditions,
    priority: Medium,
    delay: min_delay,
  )
}

fn no_conditions(
  character: world.MobileInternal,
) -> Result(world.MobileInternal, String) {
  Ok(character)
}

///
/// Business logic for actions
/// 
fn do_remove_item(conn: Conn, search_term: String) -> Conn {
  let self = conn.character_get(conn)
  let equipment = self.equipment

  let result = {
    let err = world.UnknownItem(search_term:, verb: "wearing")
    let keyword_actor = conn.named_actors(conn).keyword
    use keyword_id <- result.try(
      keyword.to_id(keyword_actor, search_term)
      |> result.replace_error(err),
    )
    let found =
      my_dict.find_nth(equipment, 1, fn(_wear_slot, wearing) {
        case wearing {
          world.EmptySlot -> False
          world.Wearing(item) -> item_matches(item, keyword_id)
        }
      })

    case found {
      Ok(#(wear_slot, world.Wearing(item))) -> Ok(#(wear_slot, item))
      _ -> Error(err)
    }
  }

  case result {
    Ok(#(wear_slot, item_instance)) -> {
      let named_actors.Lookup(items:, ..) = conn.named_actors(conn)
      world.MobileInternal(
        ..self,
        equipment: dict.insert(equipment, wear_slot, world.EmptySlot),
        inventory: [item_instance, ..self.inventory],
      )
      |> conn.character_put(conn, _)
      |> conn.renderln(render.item_remove(items, item_instance))
      |> conn.prompt
    }

    Error(error) -> {
      conn |> conn.renderln(render.error_item(error)) |> conn.prompt
    }
  }
}

fn do_wear_item(conn: Conn, search_term: String) -> Conn {
  let self = conn.character_get(conn)
  let result = {
    use item_instance <- result.try(
      find_item(conn, self.inventory, search_term)
      |> result.map_error(fn(_) {
        world.UnknownItem(search_term:, verb: "carrying")
      }),
    )
    let lookup = conn.named_actors(conn)
    use item <- result.try(items.load_from_instance(lookup.items, item_instance))
    let wear_slot = item.wear_slot
    use <- bool.lazy_guard(wear_slot == world.CannotWear, fn() {
      Error(world.CannotBeWorn(item:))
    })
    case dict.get(self.equipment, wear_slot) {
      // Update if wear slot is empty and available..
      Ok(world.EmptySlot) -> {
        Ok(#(wear_slot, item_instance, item))
      }
      // ..else if already occupied..
      Ok(world.Wearing(worn_item_instance)) ->
        case items.load_from_instance(lookup.items, worn_item_instance) {
          Ok(item) -> Error(world.WearSlotFull(wear_slot:, item:))
          Error(error) -> Error(error)
        }
      //..or missing
      Error(Nil) -> Error(world.WearSlotMissing(wear_slot:))
    }
  }

  case result {
    Ok(#(wear_slot, item_instance, item)) -> {
      let updated_character = {
        let equipment =
          dict.insert(self.equipment, wear_slot, world.Wearing(item_instance))
        let instance_id = item_instance.id
        let inventory =
          list.filter(self.inventory, fn(x) { x.id != instance_id })
        world.MobileInternal(..self, equipment:, inventory:)
      }

      conn
      |> conn.character_put(updated_character)
      |> conn.renderln(render.item_wear(item))
      |> conn.prompt
    }

    Error(error) ->
      conn |> conn.renderln(render.error_item(error)) |> conn.prompt
  }
}

///
/// Helper Functions
/// 
fn item_matches(item_instance: world.ItemInstance, search_term: Int) -> Bool {
  list.contains(item_instance.keywords, search_term)
}

fn find_item(
  conn: Conn,
  inventory: List(world.ItemInstance),
  keyword: String,
) -> Result(world.ItemInstance, Nil) {
  let keyword_actor = conn.named_actors(conn).keyword
  use keyword_id <- result.try(keyword.to_id(keyword_actor, keyword))
  list.find(inventory, item_matches(_, keyword_id))
}
