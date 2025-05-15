import ming/character/conn.{type Conn, type NextController, NextController}
import ming/character/controller.{type Flash, CharacterFlash}
import ming/character/events
import ming/character/view/login_view
import ming/world.{type ControllerMessage, Mobile, RoomSentEvent}

pub fn new(name: String) -> NextController {
  NextController(init: init, recv: recv, flash: CharacterFlash(name))
}

fn init(conn: Conn, flash: Flash) -> Conn {
  let assert CharacterFlash(name: name) = flash
  let character = conn.get_character(conn, False)

  conn
  |> conn.put_character(Mobile(..character, name: name))
  |> conn.renderln(login_view.greeting(name))
}

fn recv(conn: Conn, msg: ControllerMessage) -> Conn {
  case msg {
    RoomSentEvent(event) -> events.route(conn, event)
    _ -> conn
  }
}
