//// This module contains the code to run the sql queries defined in
//// `./src/lore/world/sql`.
//// > 🐿️ This module was generated automatically using v4.4.2 of
//// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
////

import gleam/dynamic/decode
import gleam/option.{type Option}
import pog

/// A row you get from running the `containers` query
/// defined in `./src/lore/world/sql/containers.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.4.2 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type ContainersRow {
  ContainersRow(container_id: Int, item_id: Int)
}

/// Runs the `containers` query
/// defined in `./src/lore/world/sql/containers.sql`.
///
/// > 🐿️ This function was generated automatically using v4.4.2 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn containers(
  db: pog.Connection,
) -> Result(pog.Returned(ContainersRow), pog.QueryError) {
  let decoder = {
    use container_id <- decode.field(0, decode.int)
    use item_id <- decode.field(1, decode.int)
    decode.success(ContainersRow(container_id:, item_id:))
  }

  "SELECT container_id, item_id FROM container_item;
"
  |> pog.query
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `doors` query
/// defined in `./src/lore/world/sql/doors.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.4.2 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type DoorsRow {
  DoorsRow(door_id: Int, access_state: AccessState)
}

/// Runs the `doors` query
/// defined in `./src/lore/world/sql/doors.sql`.
///
/// > 🐿️ This function was generated automatically using v4.4.2 of
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

  "SELECT door_id, access_state FROM door
WHERE is_active = TRUE;
"
  |> pog.query
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `exits` query
/// defined in `./src/lore/world/sql/exits.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.4.2 of the
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
/// > 🐿️ This function was generated automatically using v4.4.2 of
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

  "SELECT
  e.exit_id,
  e.keyword,
  e.from_room_id,
  e.to_room_id,
  d.door_id
FROM exit as e
LEFT JOIN door_side as d
  ON e.exit_id = d.exit_id AND d.is_active
WHERE e.is_active = TRUE;
"
  |> pog.query
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `item_spawns` query
/// defined in `./src/lore/world/sql/item_spawns.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.4.2 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type ItemSpawnsRow {
  ItemSpawnsRow(
    item_spawn_id: Int,
    item_id: Int,
    room_id: Int,
    spawn_group_id: Int,
  )
}

/// Runs the `item_spawns` query
/// defined in `./src/lore/world/sql/item_spawns.sql`.
///
/// > 🐿️ This function was generated automatically using v4.4.2 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn item_spawns(
  db: pog.Connection,
) -> Result(pog.Returned(ItemSpawnsRow), pog.QueryError) {
  let decoder = {
    use item_spawn_id <- decode.field(0, decode.int)
    use item_id <- decode.field(1, decode.int)
    use room_id <- decode.field(2, decode.int)
    use spawn_group_id <- decode.field(3, decode.int)
    decode.success(ItemSpawnsRow(
      item_spawn_id:,
      item_id:,
      room_id:,
      spawn_group_id:,
    ))
  }

  "SELECT * from item_spawn;
"
  |> pog.query
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `items` query
/// defined in `./src/lore/world/sql/items.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.4.2 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type ItemsRow {
  ItemsRow(
    item_id: Int,
    name: String,
    short: String,
    long: String,
    keywords: List(String),
    container_id: Option(Int),
  )
}

/// Runs the `items` query
/// defined in `./src/lore/world/sql/items.sql`.
///
/// > 🐿️ This function was generated automatically using v4.4.2 of
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
    use container_id <- decode.field(5, decode.optional(decode.int))
    decode.success(ItemsRow(
      item_id:,
      name:,
      short:,
      long:,
      keywords:,
      container_id:,
    ))
  }

  "SELECT
  i.item_id,
  i.name,
  i.short,
  i.long,
  i.keywords,
  c.container_id
FROM item as i
LEFT JOIN container as c
  ON c.item_id = i.item_id;
"
  |> pog.query
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `map_edges` query
/// defined in `./src/lore/world/sql/map_edges.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.4.2 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type MapEdgesRow {
  MapEdgesRow(from_room_id: Int, to_room_id: Int)
}

/// Runs the `map_edges` query
/// defined in `./src/lore/world/sql/map_edges.sql`.
///
/// > 🐿️ This function was generated automatically using v4.4.2 of
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
/// > 🐿️ This type definition was generated automatically using v4.4.2 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type MapNodesRow {
  MapNodesRow(room_id: Int, symbol: String, x: Int, y: Int, z: Int)
}

/// Runs the `map_nodes` query
/// defined in `./src/lore/world/sql/map_nodes.sql`.
///
/// > 🐿️ This function was generated automatically using v4.4.2 of
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

/// A row you get from running the `mob_spawns` query
/// defined in `./src/lore/world/sql/mob_spawns.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.4.2 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type MobSpawnsRow {
  MobSpawnsRow(
    mob_spawn_id: Int,
    spawn_group_id: Int,
    mobile_id: Int,
    room_id: Int,
  )
}

/// Runs the `mob_spawns` query
/// defined in `./src/lore/world/sql/mob_spawns.sql`.
///
/// > 🐿️ This function was generated automatically using v4.4.2 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn mob_spawns(
  db: pog.Connection,
) -> Result(pog.Returned(MobSpawnsRow), pog.QueryError) {
  let decoder = {
    use mob_spawn_id <- decode.field(0, decode.int)
    use spawn_group_id <- decode.field(1, decode.int)
    use mobile_id <- decode.field(2, decode.int)
    use room_id <- decode.field(3, decode.int)
    decode.success(MobSpawnsRow(
      mob_spawn_id:,
      spawn_group_id:,
      mobile_id:,
      room_id:,
    ))
  }

  "SELECT * from mob_spawn;
"
  |> pog.query
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `mobile_by_id` query
/// defined in `./src/lore/world/sql/mobile_by_id.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.4.2 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type MobileByIdRow {
  MobileByIdRow(
    mobile_id: Int,
    room_id: Int,
    name: String,
    short: String,
    keywords: List(String),
  )
}

/// Runs the `mobile_by_id` query
/// defined in `./src/lore/world/sql/mobile_by_id.sql`.
///
/// > 🐿️ This function was generated automatically using v4.4.2 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn mobile_by_id(
  db: pog.Connection,
  arg_1: Int,
) -> Result(pog.Returned(MobileByIdRow), pog.QueryError) {
  let decoder = {
    use mobile_id <- decode.field(0, decode.int)
    use room_id <- decode.field(1, decode.int)
    use name <- decode.field(2, decode.string)
    use short <- decode.field(3, decode.string)
    use keywords <- decode.field(4, decode.list(decode.string))
    decode.success(MobileByIdRow(mobile_id:, room_id:, name:, short:, keywords:))
  }

  "SELECT * from mobile where mobile_id = $1;
"
  |> pog.query
  |> pog.parameter(pog.int(arg_1))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `rooms` query
/// defined in `./src/lore/world/sql/rooms.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.4.2 of the
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
/// > 🐿️ This function was generated automatically using v4.4.2 of
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

  "SELECT * from room;
"
  |> pog.query
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `rooms_by_zone_id` query
/// defined in `./src/lore/world/sql/rooms_by_zone_id.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.4.2 of the
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
/// > 🐿️ This function was generated automatically using v4.4.2 of
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
WHERE zone_id = $1
"
  |> pog.query
  |> pog.parameter(pog.int(arg_1))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `socials` query
/// defined in `./src/lore/world/sql/socials.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.4.2 of the
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
/// > 🐿️ This function was generated automatically using v4.4.2 of
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
FROM social
"
  |> pog.query
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `spawn_groups` query
/// defined in `./src/lore/world/sql/spawn_groups.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.4.2 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type SpawnGroupsRow {
  SpawnGroupsRow(
    spawn_group_id: Int,
    reset_freq: Int,
    is_enabled: Bool,
    is_despawn_on_reset: Bool,
  )
}

/// Runs the `spawn_groups` query
/// defined in `./src/lore/world/sql/spawn_groups.sql`.
///
/// > 🐿️ This function was generated automatically using v4.4.2 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn spawn_groups(
  db: pog.Connection,
) -> Result(pog.Returned(SpawnGroupsRow), pog.QueryError) {
  let decoder = {
    use spawn_group_id <- decode.field(0, decode.int)
    use reset_freq <- decode.field(1, decode.int)
    use is_enabled <- decode.field(2, decode.bool)
    use is_despawn_on_reset <- decode.field(3, decode.bool)
    decode.success(SpawnGroupsRow(
      spawn_group_id:,
      reset_freq:,
      is_enabled:,
      is_despawn_on_reset:,
    ))
  }

  "SELECT * FROM spawn_group;
"
  |> pog.query
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `zones` query
/// defined in `./src/lore/world/sql/zones.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.4.2 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type ZonesRow {
  ZonesRow(zone_id: Int, name: String)
}

/// Runs the `zones` query
/// defined in `./src/lore/world/sql/zones.sql`.
///
/// > 🐿️ This function was generated automatically using v4.4.2 of
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
/// > 🐿️ This type definition was generated automatically using v4.4.2 of the
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
