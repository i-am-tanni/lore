import ming/character/conn.{type Conn}
import ming/character/events/move_event
import ming/world.{
  type CharacterEvent, type Event, type RoomMessage, MoveNotifyArrive,
  MoveNotifyDepart,
}

/// Route the event to the handler given the received event data.
/// 
pub fn route(conn: Conn, event: Event(CharacterEvent, RoomMessage)) -> Conn {
  case event.data {
    MoveNotifyArrive(..) -> move_event.notify_arrive(conn, event)
    MoveNotifyDepart(..) -> move_event.notify_depart(conn, event)
  }
}
