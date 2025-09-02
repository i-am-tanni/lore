import gleam/erlang/process
import gleam/int
import gleam/otp/actor
import gleam/otp/static_supervisor
import gleam/otp/supervision
import gleam/string
import glisten
import logging
import lore/server/telnet/protocol
import lore/world/kickoff
import lore/world/system_tables

pub type ServerStartError {
  //ReadEnvFileError(dotenv.Error)
  //CannotReadEnvVar(env.Error)
  StartError(actor.StartError)
}

pub fn main() {
  let server_ip = "127.0.0.1"
  let port = 4444
  logging.configure()

  let system_tables =
    system_tables.Lookup(
      zone: process.new_name("zone_registry"),
      room: process.new_name("room_registry"),
      character: process.new_name("character_registry"),
      communication: process.new_name("comms"),
      presence: process.new_name("presence"),
      mapper: process.new_name("mapper"),
      users: process.new_name("users"),
      items: process.new_name("items"),
    )

  let start_result =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.add(system_tables.supervised(system_tables))
    |> static_supervisor.add(kickoff.supervised(system_tables))
    |> static_supervisor.add(telnet_supervised(server_ip, port, system_tables))
    |> static_supervisor.start()

  case start_result {
    Ok(_) -> {
      let start_msg =
        "Server started! " <> server_ip <> ":" <> int.to_string(port)

      logging.log(logging.Info, start_msg)
      process.sleep_forever()
    }

    Error(error) ->
      logging.log(logging.Critical, "Cannot start: " <> string.inspect(error))
  }
}

fn telnet_supervised(
  server_ip: String,
  port: Int,
  system_tables: system_tables.Lookup,
) -> supervision.ChildSpecification(static_supervisor.Supervisor) {
  // define init function to be ran on each new telnet connection
  let init_connection = fn(conn) {
    // the protocol module handles all telent I/O
    protocol.init(conn, system_tables)
  }

  glisten.new(init_connection, protocol.recv)
  |> glisten.bind(server_ip)
  |> glisten.supervised(port)
}
