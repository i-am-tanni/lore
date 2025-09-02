//// Move events as perceived by a character.
////

import gleam/bool
import lore/character/conn.{type Conn}
import lore/character/view/move_view
import lore/world.{type Id, type Room}
import lore/world/event.{
  type CharacterEvent, type Event, type RoomMessage, NotifyArriveData,
  NotifyDepartData,
}

/// The zone communicates to teh characer that the move is official,
/// so the first thing they do is update their room id to the destination room.
/// 
pub fn move_commit(
  conn: Conn,
  _event: Event(CharacterEvent, RoomMessage),
  to_room_id: Id(Room),
) -> Conn {
  let character = conn.get_character(conn)
  let update = world.MobileInternal(..character, room_id: to_room_id)

  conn
  |> conn.put_character(update)
}

pub fn notify_arrive(
  conn: Conn,
  event: Event(CharacterEvent, RoomMessage),
  data: event.NotifyArriveData,
) -> Conn {
  let self = conn.get_character(conn)
  // Discard if acting_character
  use <- bool.guard(event.is_from_acting_character(event, self), conn)
  let NotifyArriveData(enter_keyword:, ..) = data
  conn.renderln(
    conn,
    move_view.notify_arrive(event.acting_character, enter_keyword),
  )
  |> conn.prompt()
}

pub fn notify_depart(
  conn: Conn,
  event: Event(CharacterEvent, RoomMessage),
  data: event.NotifyDepartData,
) -> Conn {
  let NotifyDepartData(exit_keyword:, ..) = data
  conn
  |> conn.renderln(move_view.notify_depart(event.acting_character, exit_keyword))
  |> conn.prompt()
}

pub fn notify_spawn(
  conn: Conn,
  event: Event(CharacterEvent, RoomMessage),
) -> Conn {
  conn.renderln(conn, move_view.notify_spawn(event.acting_character))
  |> conn.prompt()
}
