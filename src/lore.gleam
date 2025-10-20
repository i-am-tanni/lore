import envoy
import gleam/erlang/process
import gleam/io
import gleam/otp/actor
import gleam/otp/factory_supervisor
import gleam/otp/static_supervisor
import gleam/otp/supervision
import gleam/result
import gleam/string
import glisten
import logging
import lore/character
import lore/server/telnet/protocol
import lore/world/kickoff
import lore/world/system_tables
import pog

pub type ServerStartError {
  MissingEnvVar(var: String)
  StartError(actor.StartError)
}

pub fn main() {
  let start_result = {
    use server_ip <- result.try(env_var("SERVER_IP"))
    use port <- result.try(env_var("PORT"))
    use database_name <- result.try(env_var("DB_NAME"))

    logging.configure()

    let system_tables =
      system_tables.Lookup(
        db: process.new_name("db"),
        zone: process.new_name("zone_registry"),
        room: process.new_name("room_registry"),
        character: process.new_name("character_registry"),
        communication: process.new_name("comms"),
        presence: process.new_name("presence"),
        mapper: process.new_name("mapper"),
        users: process.new_name("users"),
        items: process.new_name("items"),
        socials: process.new_name("socials"),
        mob_factory: process.new_name("mob_factory"),
      )

    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.add(start_database_connection(
      system_tables.db,
      server_ip,
      database_name,
    ))
    |> static_supervisor.add(system_tables.supervised(system_tables))
    |> static_supervisor.add(mob_factory_supervised(system_tables))
    // kickoff is a lazy function b/c its dependent on the db being available
    |> static_supervisor.add(
      supervision.supervisor(fn() { kickoff.supervisor(system_tables) }),
    )
    |> static_supervisor.add(telnet_supervised(
      server_ip,
      string_to_int(port),
      system_tables,
    ))
    |> static_supervisor.start()
    |> result.map_error(StartError)
    |> result.replace(#(server_ip, port))
  }

  case start_result {
    Ok(#(server_ip, port)) -> {
      let start_msg = "Server started! " <> server_ip <> ":" <> port

      logging.log(logging.Info, start_msg)
      process.sleep_forever()
    }

    Error(error) -> io.print_error(string.inspect(error))
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

pub fn mob_factory_supervised(system_tables: system_tables.Lookup) {
  factory_supervisor.worker_child(character.start_character(_, system_tables))
  |> factory_supervisor.named(system_tables.mob_factory)
  |> factory_supervisor.supervised
}

@external(erlang, "erlang", "binary_to_integer")
fn string_to_int(string: String) -> Int
