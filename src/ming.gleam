import gleam/erlang/process
import gleam/int
import gleam/string
import glenvy/dotenv
import glenvy/env
import glisten.{type ConnectionInfo}
import glisten/internal/listener
import logging
import ming/character/controller/login_controller
import ming/server/lib.{try_map_err}
import ming/server/telnet/protocol

pub type ServerStartError {
  ReadEnvFileError(dotenv.Error)
  CannotReadEnvVar(env.Error)
  StartError(glisten.StartError)
  CallError(process.CallError(listener.State))
}

pub fn main() {
  logging.configure()
  case telnet_server_start() {
    Ok(info) -> {
      logging.log(
        logging.Info,
        "Listening on "
          <> glisten.ip_address_to_string(info.ip_address)
          <> " at port "
          <> int.to_string(info.port),
      )
      process.sleep_forever()
    }

    Error(error) -> {
      logging.log(
        logging.Alert,
        "Unable to start server: " <> string.inspect(error),
      )
    }
  }
}

fn telnet_server_start() -> Result(ConnectionInfo, ServerStartError) {
  // load env variables
  use _ <- try_map_err(dotenv.load(), ReadEnvFileError)
  use port <- try_map_err(env.get_int("PORT"), CannotReadEnvVar)
  use server_ip <- try_map_err(env.get_string("SERVER_IP"), CannotReadEnvVar)

  // define init function to be ran on each new telnet connection
  let init_connection = fn(conn) {
    // the protocol module handles all telent I/O
    protocol.init(conn, init: login_controller.new())
  }

  // pass telnet connection init and recv functions to handler and start
  let start_result =
    glisten.handler(init_connection, protocol.recv)
    |> glisten.bind(server_ip)
    |> glisten.start_server(port)

  use server <- try_map_err(start_result, StartError)
  use info <- try_map_err(glisten.get_server_info(server, 5000), CallError)
  Ok(info)
}
