import envoy
import gleam/erlang/process
import gleam/io
import gleam/otp/actor
import gleam/otp/static_supervisor
import gleam/otp/supervision
import gleam/result.{try}
import gleam/string
import mist
import pog
import web_editor/router
import wisp
import wisp/wisp_mist

pub type ServerStartError {
  MissingEnvVar(var: String)
  StartError(actor.StartError)
}

pub fn main() {
  wisp.configure_logger()
  let result = {
    use secret_key_base <- try(env_var("SECRET_KEY_BASE"))
    use db_name <- try(env_var("DB_NAME"))
    use server_ip <- try(env_var("SERVER_IP"))
    let db = process.new_name("db")

    static_supervisor.new(static_supervisor.RestForOne)
    |> static_supervisor.add(start_database_connection(db, server_ip, db_name))
    |> static_supervisor.add(
      supervision.supervisor(fn() { start_http(db, secret_key_base) }),
    )
    |> static_supervisor.start
    |> result.map_error(StartError)
  }

  case result {
    Ok(_) -> process.sleep_forever()
    Error(error) -> io.println_error(string.inspect(error))
  }
}

pub fn start_http(db: process.Name(pog.Message), secret_key_base: String) {
  wisp_mist.handler(router.handle_request(_, db), secret_key_base)
  |> mist.new
  |> mist.port(8000)
  |> mist.start
}

pub fn start_database_connection(
  pool_name: process.Name(pog.Message),
  server_ip: String,
  database_name: String,
) {
  let pool_child =
    pog.default_config(pool_name)
    |> pog.host(server_ip)
    |> pog.database(database_name)
    |> pog.pool_size(15)
    |> pog.supervised

  static_supervisor.new(static_supervisor.RestForOne)
  |> static_supervisor.add(pool_child)
  |> static_supervisor.supervised
}

fn env_var(name: String) -> Result(String, ServerStartError) {
  envoy.get(name)
  |> result.replace_error(MissingEnvVar(name))
}
