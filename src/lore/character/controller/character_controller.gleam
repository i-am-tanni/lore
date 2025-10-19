import lore/character/character_registry
import lore/character/command
import lore/character/conn.{type Conn}
import lore/character/controller.{type CharacterFlash}
import lore/character/events
import lore/character/view/communication_view
import lore/world.{Id}
import lore/world/system_tables

pub fn init(conn: Conn, _flash: CharacterFlash) -> Conn {
  let system_tables.Lookup(character:, ..) = conn.system_tables(conn)
  let world.MobileInternal(id:, ..) = conn.get_character(conn)
  let self = conn.self(conn)
  character_registry.register(character, id, self)
  conn.spawn(conn, Id(1))
}

pub fn recv(
  conn: Conn,
  _flash: CharacterFlash,
  request: controller.Request,
) -> Conn {
  let is_player = conn.is_player(conn)
  case request {
    controller.RoomToCharacter(event) if is_player ->
      events.route_player(conn, event)

    controller.RoomToCharacter(event) -> events.route_npc(conn, event)

    controller.Chat(data) if is_player ->
      conn
      |> conn.renderln(communication_view.chat(data))
      |> conn.prompt()

    controller.Chat(_) -> conn

    controller.UserSentCommand(command) -> command.parse(conn, command)

    controller.ZoneToCharacter(_) -> conn
  }
}
