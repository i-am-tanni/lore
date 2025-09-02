//// Route the event to the handler given the received event data.
////

import lore/character/conn.{type Conn}
import lore/character/events/item_event
import lore/character/events/move_event
import lore/character/view
import lore/character/view/character_view
import lore/character/view/communication_view
import lore/character/view/door_view
import lore/character/view/error_view
import lore/world
import lore/world/event.{type CharacterEvent, type Event, type RoomMessage}

pub fn route_player(
  conn: Conn,
  event: Event(CharacterEvent, RoomMessage),
) -> Conn {
  case event.data {
    event.ActFailed(reason) ->
      conn
      |> conn.renderln(error_view.room_request_error(reason))
      |> conn.prompt()
    event.MoveNotifyArrive(data) -> move_event.notify_arrive(conn, event, data)
    event.MoveNotifyDepart(data) -> move_event.notify_depart(conn, event, data)
    event.MoveCommit(data) -> move_event.move_commit(conn, event, data)
    event.DoorNotify(data) -> notify(conn, event, data, door_view.notify)
    event.Communication(data) ->
      notify(conn, event, data, communication_view.notify)
    event.ItemGetNotify(item) -> item_event.get(conn, event, item)
    event.ItemDropNotify(item) -> item_event.drop(conn, event, item)
    event.ItemInspect(item) -> item_event.look_at(conn, event, item)
    event.MobileInspectRequest(by: requester) -> {
      echo "Recieved inspection request"
      conn.character_event(
        conn,
        event.MobileInspectResponse(conn.get_character(conn)),
        send: requester,
      )
    }
    event.MobileInspectResponse(character:) ->
      conn
      |> conn.renderln(character_view.look_at(character))
      |> conn.prompt()
  }
}

fn notify(
  conn: Conn,
  event: Event(CharacterEvent, a),
  data: data,
  render_fun: fn(world.MobileInternal, world.Mobile, data) -> view.View,
) -> Conn {
  let view = render_fun(conn.get_character(conn), event.acting_character, data)
  conn
  |> conn.renderln(view)
  |> conn.prompt()
}
