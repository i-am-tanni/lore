import argus
import gleam/result.{try}
import gleam/string
import lore/character/conn.{type Conn}
import lore/character/controller.{
  type LoginFlash, CharacterFlash, LoginFlash, UserSentCommand,
}
import lore/character/pronoun
import lore/character/users
import lore/character/view
import lore/character/view/login_view
import lore/world.{Id}
import lore/world/sql
import lore/world/system_tables
import pog
import splitter

pub type LoginError {
  InputEmpty
  DatabaseError(pog.QueryError)
  NotFound(String)
}

pub type PasswordError {
  HashError(argus.HashError)
  Blank
}

pub fn init(conn: Conn, flash: LoginFlash) -> Conn {
  let flash = LoginFlash(..flash, score: 12)

  conn
  |> flash_put(flash)
  |> conn.renderln(login_view.login())
  |> conn.renderln(login_view.name())
}

pub fn recv(conn: Conn, flash: LoginFlash, msg: controller.Request) -> Conn {
  case msg {
    UserSentCommand(text: string) -> handle_text(conn, flash, string)
    _ -> conn
  }
}

fn handle_text(conn: Conn, flash: LoginFlash, input: String) -> Conn {
  case flash.stage {
    controller.LoginName -> account_name(conn, flash, input)
    controller.LoginPassword -> password(conn, flash, input)
    controller.LoginConfirmNewAccount -> new_account_confirm(conn, flash, input)
    controller.LoginNewPassword -> new_password(conn, flash, input)
    controller.LoginConfirmNewPassword ->
      new_password_confirm(conn, flash, input)
  }
}

fn account_name(conn: Conn, flash: LoginFlash, input: String) -> Conn {
  let result = {
    use name <- try(parse(flash.splitter, input))
    let name = name |> string.lowercase |> string.capitalise
    let system_tables.Lookup(db:, ..) = conn.system_tables(conn)
    let db = pog.named_connection(db)
    use account <- try(query1(sql.account_get(db, name), name))

    conn
    |> flash_put(
      LoginFlash(
        ..flash,
        stage: controller.LoginPassword,
        password_hash: account.password_hash,
        name: account.name,
      ),
    )
    |> conn.echo_disable
    |> conn.render(login_view.password(name))
    |> Ok
  }

  case result {
    Ok(conn) -> conn

    Error(NotFound(name)) -> {
      let name = name |> string.lowercase |> string.capitalise
      let update =
        LoginFlash(..flash, name:, stage: controller.LoginConfirmNewAccount)

      conn
      |> conn.render(login_view.new_name_confirm(name))
      |> flash_put(update)
    }

    Error(InputEmpty) -> {
      use score <- penalize(conn, flash, amount: 3)
      conn
      |> flash_put(LoginFlash(..flash, score:))
      |> conn.renderln(login_view.name())
    }

    Error(DatabaseError(_)) -> conn.terminate(conn)
  }
}

fn new_account_confirm(conn: Conn, flash: LoginFlash, input: String) -> Conn {
  let #(answer, _) = splitter.split_before(flash.splitter, input)

  case string.lowercase(answer) {
    "y" | "ye" | "yes" | "" ->
      conn
      |> conn.render(login_view.new_password1())
      |> conn.echo_disable
      |> flash_put(LoginFlash(..flash, stage: controller.LoginNewPassword))

    "n" | "no" -> {
      use score <- penalize(conn, flash, amount: 4)
      conn
      |> conn.render(login_view.name_abort())
      |> flash_put(
        LoginFlash(..flash, score:, name: "", stage: controller.LoginName),
      )
    }

    _ -> {
      use score <- penalize(conn, flash, amount: 3)
      conn
      |> conn.render(login_view.new_name_confirm(flash.name))
      |> flash_put(LoginFlash(..flash, score:))
    }
  }
}

fn new_password(conn: Conn, flash: LoginFlash, input: String) -> Conn {
  let result = {
    use input <- try(
      parse(flash.splitter, input) |> result.replace_error(Blank),
    )
    use hashes <- try(
      argus.hash(argus.hasher(), input, argus.gen_salt())
      |> result.map_error(HashError),
    )
    let update =
      LoginFlash(
        ..flash,
        password_hash: hashes.encoded_hash,
        stage: controller.LoginConfirmNewPassword,
      )

    conn
    |> flash_put(update)
    |> conn.render(login_view.new_password2())
    |> Ok
  }

  case result {
    Ok(conn) -> conn
    Error(_) -> {
      use score <- penalize(conn, flash, amount: 4)
      conn
      |> conn.render(login_view.password_invalid())
      |> flash_put(LoginFlash(..flash, score:))
    }
  }
}

fn new_password_confirm(conn: Conn, flash: LoginFlash, input: String) -> Conn {
  let result = {
    use input <- try(
      parse(flash.splitter, input) |> result.replace_error(Blank),
    )
    argus.verify(flash.password_hash, input)
    |> result.map_error(HashError)
  }

  case result {
    Ok(True) -> {
      let lookup = conn.system_tables(conn)
      let db = pog.named_connection(lookup.db)
      case sql.account_put(db, flash.name, flash.password_hash) {
        Ok(_) -> login(conn, flash)
        Error(_) -> conn.terminate(conn)
      }
    }

    Ok(False) -> {
      use score <- penalize(conn, flash, amount: 4)
      conn
      |> conn.render(login_view.password_mismatch_err())
      |> flash_put(
        LoginFlash(..flash, score:, stage: controller.LoginNewPassword),
      )
    }

    Error(_) -> conn.terminate(conn)
  }
}

fn password(conn: Conn, flash: LoginFlash, input: String) -> Conn {
  let result = {
    use input <- try(
      parse(flash.splitter, input) |> result.replace_error(Blank),
    )
    argus.verify(flash.password_hash, input)
    |> result.map_error(HashError)
  }

  case result {
    Ok(True) -> login(conn, flash)

    Ok(False) -> {
      use score <- penalize(conn, flash, amount: 5)
      conn
      |> conn.render(login_view.password_err())
      |> flash_put(LoginFlash(..flash, score:, stage: controller.LoginPassword))
    }

    Error(_) -> conn.terminate(conn)
  }
}

fn login(conn: Conn, flash: LoginFlash) -> Conn {
  let name = flash.name
  let world.MobileInternal(id:, ..) = conn.character_get(conn)

  let update =
    world.MobileInternal(
      id:,
      name:,
      room_id: Id(1),
      template_id: world.Player(Id(0)),
      role: world.Admin,
      keywords: [string.lowercase(name)],
      pronouns: pronoun.Feminine,
      short: name <> " is standing here.",
      inventory: [],
      fighting: world.NoTarget,
      affects: world.affects_init(),
      hp: 20,
      hp_max: 20,
    )

  let system_tables.Lookup(user:, ..) = conn.system_tables(conn)
  users.insert(user, flash.endpoint, name:, id:)

  let next_flash = CharacterFlash(name)
  conn
  |> conn.echo_enable
  |> conn.character_put(update)
  |> conn.subscribe(world.General)
  |> conn.next_controller(controller.Character(next_flash))
}

fn query1(
  result: Result(pog.Returned(a), pog.QueryError),
  expected: String,
) -> Result(a, LoginError) {
  use returned <- try(result.map_error(result, DatabaseError))
  case returned {
    pog.Returned(count: 1, rows: [returned]) -> Ok(returned)
    _ -> Error(NotFound(expected))
  }
}

// Wrapped around conn.flash_put to add some type safety.
//
fn flash_put(conn: Conn, flash: LoginFlash) -> Conn {
  conn.flash_put(conn, controller.Login(flash))
}

fn parse(
  splitter: splitter.Splitter,
  text: String,
) -> Result(String, LoginError) {
  case splitter.split_before(splitter, text) {
    #("", _) -> Error(InputEmpty)
    #(name, _) -> Ok(name)
  }
}

// Add a penalty to the connection with control flow
// This is a substitute for a bool.lazy_guard()
//
fn penalize(
  conn: Conn,
  flash: LoginFlash,
  amount penalty: Int,
  on_success continue_with: fn(Int) -> Conn,
) -> Conn {
  case flash.score - penalty {
    // Lazily execute continue_with if points remain
    score if score > 0 -> continue_with(score)
    // ..else the connection's points are exhausted, terminate the connection
    _ -> conn |> conn.renderln(view.Leaf("\nGoodbye.")) |> conn.terminate
  }
}
