//// Move events as perceived by a character.
////

import ming/character/conn.{type Conn}
import ming/character/view/move_view
import ming/world.{
  type CharacterEvent, type Event, type RoomMessage, ActingCharacter,
  MoveNotifyArrive, MoveNotifyDepart,
}

pub fn notify_arrive(
  conn: Conn,
  event: Event(CharacterEvent, RoomMessage),
) -> Conn {
  let assert MoveNotifyArrive(from_exit: exit_option, ..) = event.data
  let assert ActingCharacter(character) = event.initiated_by
  conn.renderln(conn, move_view.notify_arrive(character, exit_option))
}

pub fn notify_depart(
  conn: Conn,
  event: Event(CharacterEvent, RoomMessage),
) -> Conn {
  let assert MoveNotifyDepart(to_exit: exit_option, ..) = event.data
  let assert ActingCharacter(character) = event.initiated_by
  conn.renderln(conn, move_view.notify_depart(character, exit_option))
}
