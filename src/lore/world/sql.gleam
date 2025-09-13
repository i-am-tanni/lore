//// This module contains the code to run the sql queries defined in
//// `./src/lore/world/sql`.
//// > 🐿️ This module was generated automatically using v4.4.1 of
//// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
////

import gleam/dynamic/decode
import gleam/option.{type Option}
import pog

/// A row you get from running the `doors` query
/// defined in `./src/lore/world/sql/doors.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.4.1 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type DoorsRow {
  DoorsRow(door_id: Int, access_state: AccessState)
}

/// Runs the `doors` query
/// defined in `./src/lore/world/sql/doors.sql`.
///
/// > 🐿️ This function was generated automatically using v4.4.1 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn doors(
  db: pog.Connection,
) -> Result(pog.Returned(DoorsRow), pog.QueryError) {
  let decoder = {
    use door_id <- decode.field(0, decode.int)
    use access_state <- decode.field(1, access_state_decoder())
    decode.success(DoorsRow(door_id:, access_state:))
  }

  "SELECT * from door;"
  |> pog.query
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `exits` query
/// defined in `./src/lore/world/sql/exits.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.4.1 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type ExitsRow {
  ExitsRow(
    exit_id: Int,
    keyword: String,
    from_room_id: Int,
    to_room_id: Int,
    door_id: Option(Int),
  )
}

/// Runs the `exits` query
/// defined in `./src/lore/world/sql/exits.sql`.
///
/// > 🐿️ This function was generated automatically using v4.4.1 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn exits(
  db: pog.Connection,
) -> Result(pog.Returned(ExitsRow), pog.QueryError) {
  let decoder = {
    use exit_id <- decode.field(0, decode.int)
    use keyword <- decode.field(1, decode.string)
    use from_room_id <- decode.field(2, decode.int)
    use to_room_id <- decode.field(3, decode.int)
    use door_id <- decode.field(4, decode.optional(decode.int))
    decode.success(ExitsRow(
      exit_id:,
      keyword:,
      from_room_id:,
      to_room_id:,
      door_id:,
    ))
  }

  "SELECT * from exit;"
  |> pog.query
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `items` query
/// defined in `./src/lore/world/sql/items.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.4.1 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type ItemsRow {
  ItemsRow(
    item_id: Int,
    name: String,
    short: String,
    long: String,
    keywords: List(String),
  )
}

/// Runs the `items` query
/// defined in `./src/lore/world/sql/items.sql`.
///
/// > 🐿️ This function was generated automatically using v4.4.1 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn items(
  db: pog.Connection,
) -> Result(pog.Returned(ItemsRow), pog.QueryError) {
  let decoder = {
    use item_id <- decode.field(0, decode.int)
    use name <- decode.field(1, decode.string)
    use short <- decode.field(2, decode.string)
    use long <- decode.field(3, decode.string)
    use keywords <- decode.field(4, decode.list(decode.string))
    decode.success(ItemsRow(item_id:, name:, short:, long:, keywords:))
  }

  "SELECT * from item;"
  |> pog.query
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `map_edges` query
/// defined in `./src/lore/world/sql/map_edges.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.4.1 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type MapEdgesRow {
  MapEdgesRow(from_room_id: Int, to_room_id: Int)
}

/// Runs the `map_edges` query
/// defined in `./src/lore/world/sql/map_edges.sql`.
///
/// > 🐿️ This function was generated automatically using v4.4.1 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn map_edges(
  db: pog.Connection,
) -> Result(pog.Returned(MapEdgesRow), pog.QueryError) {
  let decoder = {
    use from_room_id <- decode.field(0, decode.int)
    use to_room_id <- decode.field(1, decode.int)
    decode.success(MapEdgesRow(from_room_id:, to_room_id:))
  }

  "SELECT from_room_id, to_room_id from exit;"
  |> pog.query
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `map_nodes` query
/// defined in `./src/lore/world/sql/map_nodes.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.4.1 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type MapNodesRow {
  MapNodesRow(room_id: Int, symbol: String, x: Int, y: Int, z: Int)
}

/// Runs the `map_nodes` query
/// defined in `./src/lore/world/sql/map_nodes.sql`.
///
/// > 🐿️ This function was generated automatically using v4.4.1 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn map_nodes(
  db: pog.Connection,
) -> Result(pog.Returned(MapNodesRow), pog.QueryError) {
  let decoder = {
    use room_id <- decode.field(0, decode.int)
    use symbol <- decode.field(1, decode.string)
    use x <- decode.field(2, decode.int)
    use y <- decode.field(3, decode.int)
    use z <- decode.field(4, decode.int)
    decode.success(MapNodesRow(room_id:, symbol:, x:, y:, z:))
  }

  "SELECT room_id, symbol, x, y, z from room;"
  |> pog.query
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `rooms` query
/// defined in `./src/lore/world/sql/rooms.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.4.1 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type RoomsRow {
  RoomsRow(
    room_id: Int,
    name: String,
    zone_id: Int,
    symbol: String,
    x: Int,
    y: Int,
    z: Int,
    description: String,
  )
}

/// Runs the `rooms` query
/// defined in `./src/lore/world/sql/rooms.sql`.
///
/// > 🐿️ This function was generated automatically using v4.4.1 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn rooms(
  db: pog.Connection,
) -> Result(pog.Returned(RoomsRow), pog.QueryError) {
  let decoder = {
    use room_id <- decode.field(0, decode.int)
    use name <- decode.field(1, decode.string)
    use zone_id <- decode.field(2, decode.int)
    use symbol <- decode.field(3, decode.string)
    use x <- decode.field(4, decode.int)
    use y <- decode.field(5, decode.int)
    use z <- decode.field(6, decode.int)
    use description <- decode.field(7, decode.string)
    decode.success(RoomsRow(
      room_id:,
      name:,
      zone_id:,
      symbol:,
      x:,
      y:,
      z:,
      description:,
    ))
  }

  "SELECT * from room;"
  |> pog.query
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `rooms_by_zone_id` query
/// defined in `./src/lore/world/sql/rooms_by_zone_id.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.4.1 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type RoomsByZoneIdRow {
  RoomsByZoneIdRow(
    room_id: Int,
    name: String,
    zone_id: Int,
    symbol: String,
    x: Int,
    y: Int,
    z: Int,
    description: String,
  )
}

/// Runs the `rooms_by_zone_id` query
/// defined in `./src/lore/world/sql/rooms_by_zone_id.sql`.
///
/// > 🐿️ This function was generated automatically using v4.4.1 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn rooms_by_zone_id(
  db: pog.Connection,
  arg_1: Int,
) -> Result(pog.Returned(RoomsByZoneIdRow), pog.QueryError) {
  let decoder = {
    use room_id <- decode.field(0, decode.int)
    use name <- decode.field(1, decode.string)
    use zone_id <- decode.field(2, decode.int)
    use symbol <- decode.field(3, decode.string)
    use x <- decode.field(4, decode.int)
    use y <- decode.field(5, decode.int)
    use z <- decode.field(6, decode.int)
    use description <- decode.field(7, decode.string)
    decode.success(RoomsByZoneIdRow(
      room_id:,
      name:,
      zone_id:,
      symbol:,
      x:,
      y:,
      z:,
      description:,
    ))
  }

  "SELECT * from room
WHERE zone_id = $1"
  |> pog.query
  |> pog.parameter(pog.int(arg_1))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `socials` query
/// defined in `./src/lore/world/sql/socials.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.4.1 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type SocialsRow {
  SocialsRow(
    command: String,
    char_auto: String,
    char_no_arg: String,
    char_found: String,
    others_auto: String,
    others_found: String,
    others_no_arg: String,
    vict_found: String,
  )
}

/// Runs the `socials` query
/// defined in `./src/lore/world/sql/socials.sql`.
///
/// > 🐿️ This function was generated automatically using v4.4.1 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn socials(
  db: pog.Connection,
) -> Result(pog.Returned(SocialsRow), pog.QueryError) {
  let decoder = {
    use command <- decode.field(0, decode.string)
    use char_auto <- decode.field(1, decode.string)
    use char_no_arg <- decode.field(2, decode.string)
    use char_found <- decode.field(3, decode.string)
    use others_auto <- decode.field(4, decode.string)
    use others_found <- decode.field(5, decode.string)
    use others_no_arg <- decode.field(6, decode.string)
    use vict_found <- decode.field(7, decode.string)
    decode.success(SocialsRow(
      command:,
      char_auto:,
      char_no_arg:,
      char_found:,
      others_auto:,
      others_found:,
      others_no_arg:,
      vict_found:,
    ))
  }

  "SELECT command, char_auto, char_no_arg, char_found, others_auto, others_found, others_no_arg, vict_found 
FROM social"
  |> pog.query
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `zones` query
/// defined in `./src/lore/world/sql/zones.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.4.1 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type ZonesRow {
  ZonesRow(zone_id: Int, name: String)
}

/// Runs the `zones` query
/// defined in `./src/lore/world/sql/zones.sql`.
///
/// > 🐿️ This function was generated automatically using v4.4.1 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn zones(
  db: pog.Connection,
) -> Result(pog.Returned(ZonesRow), pog.QueryError) {
  let decoder = {
    use zone_id <- decode.field(0, decode.int)
    use name <- decode.field(1, decode.string)
    decode.success(ZonesRow(zone_id:, name:))
  }

  "SELECT * from zone"
  |> pog.query
  |> pog.returning(decoder)
  |> pog.execute(db)
}

// --- Enums -------------------------------------------------------------------

/// Corresponds to the Postgres `access_state` enum.
///
/// > 🐿️ This type definition was generated automatically using v4.4.1 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type AccessState {
  Open
  Closed
}

fn access_state_decoder() -> decode.Decoder(AccessState) {
  use access_state <- decode.then(decode.string)
  case access_state {
    "open" -> decode.success(Open)
    "closed" -> decode.success(Closed)
    _ -> decode.failure(Open, "AccessState")
  }
}
