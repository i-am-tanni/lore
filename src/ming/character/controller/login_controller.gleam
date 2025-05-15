import gleam/bit_array
import ming/character/conn.{type Conn, type NextController, NextController}
import ming/character/controller.{type Flash, LoginFlash, LoginName}
import ming/character/controller/character_controller
import ming/character/view/login_view
import ming/world.{type ControllerMessage, UserSentCommand}

pub fn new() -> NextController {
  let init_flash = LoginFlash(name: "", stage: LoginName, score: 120)
  NextController(init: init, recv: recv, flash: init_flash)
}

fn init(conn: Conn, _flash: Flash) -> Conn {
  conn
  |> conn.renderln(login_view.login())
  |> conn.renderln(login_view.name())
}

fn recv(conn: Conn, msg: ControllerMessage) -> Conn {
  case msg {
    UserSentCommand(text: string) -> handle_text(conn, string)
    _ -> conn
  }
}

fn handle_text(conn: Conn, text: String) -> Conn {
  let assert LoginFlash(stage: stage, score: score, ..) = conn.get_flash(conn)
  case stage {
    _ if score <= 0 -> conn.terminate(conn)
    LoginName -> login_name(conn, text)
  }
}

fn login_name(conn: Conn, text: String) -> Conn {
  case text {
    "\r\n" -> {
      let assert LoginFlash(score: score, ..) as flash = conn.get_flash(conn)
      let update = LoginFlash(..flash, score: score - 40)
      conn
      |> conn.renderln(login_view.name())
      |> conn.put_flash(update)
    }

    name -> {
      let name = bit_array.from_string(name)
      let assert Ok(name) =
        bit_array.slice(name, 0, bit_array.byte_size(name) - 2)
      let assert Ok(name) = bit_array.to_string(name)
      conn.put_controller(conn, character_controller.new(name))
    }
  }
}
