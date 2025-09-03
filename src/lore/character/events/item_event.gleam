import gleam/list
import gleam/result
import lore/character/conn.{type Conn}
import lore/character/view/item_view
import lore/world
import lore/world/event.{type CharacterEvent, type Event, type RoomMessage}
import lore/world/items
import lore/world/system_tables

pub fn get(
  conn: Conn,
  event: Event(CharacterEvent, RoomMessage),
  item_instance: world.ItemInstance,
) -> Conn {
  let result = {
    use item <- result.try(load_item(conn, item_instance))
    let self = conn.get_character(conn)
    case event.is_from_acting_character(event, self) {
      True -> {
        let update = [item_instance, ..self.inventory]

        conn
        |> conn.put_character(world.MobileInternal(..self, inventory: update))
        |> conn.renderln(item_view.get(self, event.acting_character, item))
        |> Ok
      }

      False ->
        conn.renderln(conn, item_view.get(self, event.acting_character, item))
        |> Ok
    }
  }

  case result {
    Ok(update) -> conn.prompt(update)
    Error(Nil) -> conn
  }
}

pub fn drop(
  conn: Conn,
  event: Event(CharacterEvent, RoomMessage),
  item_instance: world.ItemInstance,
) -> Conn {
  let result = {
    use item <- result.try(load_item(conn, item_instance))
    let self = conn.get_character(conn)
    case event.is_from_acting_character(event, self) {
      True -> {
        let update =
          list.filter(self.inventory, fn(x) { item_instance.id != x.id })

        conn
        |> conn.put_character(world.MobileInternal(..self, inventory: update))
        |> conn.renderln(item_view.drop(self, event.acting_character, item))
        |> Ok
      }

      False ->
        conn.renderln(conn, item_view.drop(self, event.acting_character, item))
        |> Ok
    }
  }

  case result {
    Ok(update) -> conn.prompt(update)
    Error(Nil) -> conn
  }
}

pub fn look_at(conn: Conn, item_instance: world.ItemInstance) -> Conn {
  case load_item(conn, item_instance) {
    Ok(item) ->
      conn
      |> conn.renderln(item_view.inspect(item))
      |> conn.prompt()

    Error(Nil) -> conn
  }
}

fn load_item(
  conn: Conn,
  item_instance: world.ItemInstance,
) -> Result(world.Item, Nil) {
  let system_tables.Lookup(items:, ..) = conn.system_tables(conn)
  case item_instance.item {
    world.Loading(id) -> items.load(items, id)
    world.Loaded(item) -> Ok(item)
  }
}
