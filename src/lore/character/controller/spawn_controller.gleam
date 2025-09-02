import lore/character/conn.{type Conn}
import lore/character/controller.{type SpawnFlash}
import lore/world
import lore/world/event
import lore/world/room/presence

pub fn init(conn: Conn, flash: SpawnFlash) -> Conn {
  let room_id = flash.at
  let world.MobileInternal(id: mobile_id, ..) = conn.get_character(conn)
  let presence = flash.presence
  case presence.lookup(presence, mobile_id) {
    // Did character restart?
    Ok(present_location) if present_location != room_id -> {
      presence.notify_restart(presence, conn.self(conn), mobile_id)
      let character = conn.get_character(conn)
      let update = world.MobileInternal(..character, room_id: present_location)

      conn
      |> conn.put_character(update)
      |> conn.event(event.Rejoin)
    }

    Ok(_) -> conn

    // If character location is not already present in the world
    Error(Nil) -> conn.spawn(conn, to: room_id)
  }
}

pub fn recv(conn: Conn, _flash: SpawnFlash, _msg: controller.Request) -> Conn {
  conn
}
