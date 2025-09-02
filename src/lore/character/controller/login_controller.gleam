import gleam/bit_array
import gleam/result
import gleam/string
import lore/character/conn.{type Conn}
import lore/character/controller.{
  type LoginFlash, CharacterFlash, LoginFlash, LoginName, UserSentCommand,
}
import lore/character/pronoun
import lore/character/users
import lore/character/view/login_view
import lore/world.{Id}
import lore/world/system_tables

pub fn init(conn: Conn, _flash: LoginFlash) -> Conn {
  conn
  |> conn.renderln(login_view.login())
  |> conn.renderln(login_view.name())
}

pub fn recv(conn: Conn, flash: LoginFlash, msg: controller.Request) -> Conn {
  case msg {
    UserSentCommand(text: string) -> handle_text(conn, flash, string)
    _ -> conn
  }
}

fn handle_text(conn: Conn, flash: LoginFlash, text: String) -> Conn {
  let LoginFlash(stage: stage, score: score, ..) = flash
  case stage {
    _ if score <= 0 -> conn.terminate(conn)
    LoginName -> login_name(conn, flash, text)
  }
}

fn login_name(conn: Conn, flash: LoginFlash, text: String) -> Conn {
  case text {
    "\r\n" | "\n" | "" -> {
      let LoginFlash(score: score, ..) = flash
      let update = LoginFlash(..flash, score: score - 40)

      conn
      |> conn.renderln(login_view.name())
      |> conn.put_flash(controller.Login(update))
      |> result.unwrap(conn)
    }

    name -> {
      // Remove "\r\n" from the tail
      let name = bit_array.from_string(name)
      let assert Ok(name) =
        bit_array.slice(name, 0, bit_array.byte_size(name) - 2)
      let assert Ok(name) = bit_array.to_string(name)

      let world.MobileInternal(id:, ..) = conn.get_character(conn)

      let update =
        world.MobileInternal(
          id:,
          name:,
          room_id: Id(1),
          template_id: world.Player(Id(0)),
          keywords: [string.lowercase(name)],
          pronouns: pronoun.Feminine,
          short: name <> " is standing here.",
          inventory: [],
        )

      let system_tables.Lookup(users:, ..) = conn.system_tables(conn)
      users.insert(users, flash.portal, id, users.User(name:))

      conn
      |> conn.put_character(update)
      |> conn.subscribe(world.General)
      |> conn.put_controller(controller.Character(CharacterFlash(name)))
    }
  }
}
