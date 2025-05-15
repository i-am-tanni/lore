import gleam/dynamic/decode
import pog

/// A row you get from running the `item_insert` query
/// defined in `./src/ming/world/sql/item_insert.sql`.
///
/// > 🐿️ This type definition was generated automatically using v3.0.1 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type ItemInsertRow {
  ItemInsertRow(item_instance_id: Int)
}

/// Runs the `item_insert` query
/// defined in `./src/ming/world/sql/item_insert.sql`.
///
/// > 🐿️ This function was generated automatically using v3.0.1 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn item_insert(db, arg_1, arg_2) {
  let decoder = {
    use item_instance_id <- decode.field(0, decode.int)
    decode.success(ItemInsertRow(item_instance_id:))
  }

  "INSERT INTO instance_items(item_id, inventory_id, container_id)
VALUES($1, $2, NULL)
RETURNING(item_instance_id)"
  |> pog.query
  |> pog.parameter(pog.int(arg_1))
  |> pog.parameter(pog.int(arg_2))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `item_find_inactive_id` query
/// defined in `./src/ming/world/sql/item_find_inactive_id.sql`.
///
/// > 🐿️ This type definition was generated automatically using v3.0.1 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type ItemFindInactiveIdRow {
  ItemFindInactiveIdRow(item_instance_id: Int)
}

/// Recycle ids where possible of inactive item instances
///
/// > 🐿️ This function was generated automatically using v3.0.1 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn item_find_inactive_id(db) {
  let decoder = {
    use item_instance_id <- decode.field(0, decode.int)
    decode.success(ItemFindInactiveIdRow(item_instance_id:))
  }

  "-- Recycle ids where possible of inactive item instances
SELECT item_instance_id FROM instance_items
WHERE is_active = false
LIMIT 1
"
  |> pog.query
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// Recycle an inactive mob instance id
///
/// > 🐿️ This function was generated automatically using v3.0.1 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn mob_recycle(db, arg_1, arg_2, arg_3) {
  let decoder = decode.map(decode.dynamic, fn(_) { Nil })

  "
-- Recycle an inactive mob instance id

UPDATE instance_mobs
SET room_instance_id = $2,
    character_id = $3,
    is_player = FALSE,
    is_active = TRUE
WHERE mob_instance_id = $1"
  |> pog.query
  |> pog.parameter(pog.int(arg_1))
  |> pog.parameter(pog.int(arg_2))
  |> pog.parameter(pog.int(arg_3))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `mob_find_inactive_id` query
/// defined in `./src/ming/world/sql/mob_find_inactive_id.sql`.
///
/// > 🐿️ This type definition was generated automatically using v3.0.1 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type MobFindInactiveIdRow {
  MobFindInactiveIdRow(mob_instance_id: Int)
}

/// Recycle ids where possible of inactive mob instances
///
/// > 🐿️ This function was generated automatically using v3.0.1 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn mob_find_inactive_id(db) {
  let decoder = {
    use mob_instance_id <- decode.field(0, decode.int)
    decode.success(MobFindInactiveIdRow(mob_instance_id:))
  }

  "-- Recycle ids where possible of inactive mob instances
SELECT mob_instance_id FROM instance_mobs
WHERE is_active = false
LIMIT 1
"
  |> pog.query
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `mob_insert` query
/// defined in `./src/ming/world/sql/mob_insert.sql`.
///
/// > 🐿️ This type definition was generated automatically using v3.0.1 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type MobInsertRow {
  MobInsertRow(room_instance_id: Int)
}

/// Runs the `mob_insert` query
/// defined in `./src/ming/world/sql/mob_insert.sql`.
///
/// > 🐿️ This function was generated automatically using v3.0.1 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn mob_insert(db, arg_1, arg_2, arg_3) {
  let decoder = {
    use room_instance_id <- decode.field(0, decode.int)
    decode.success(MobInsertRow(room_instance_id:))
  }

  "INSERT INTO instance_mobs(
  character_id, 
  room_instance_id, 
  inventory_id, 
  is_active, 
  is_player
)
VALUES($1, $2, $3, TRUE, FALSE)
RETURNING(room_instance_id)
"
  |> pog.query
  |> pog.parameter(pog.int(arg_1))
  |> pog.parameter(pog.int(arg_2))
  |> pog.parameter(pog.int(arg_3))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `zone_find` query
/// defined in `./src/ming/world/sql/zone_find.sql`.
///
/// > 🐿️ This type definition was generated automatically using v3.0.1 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type ZoneFindRow {
  ZoneFindRow(zone_id: Int, name: String)
}

/// finds a zone
///
/// > 🐿️ This function was generated automatically using v3.0.1 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn zone_find(db, arg_1) {
  let decoder = {
    use zone_id <- decode.field(0, decode.int)
    use name <- decode.field(1, decode.string)
    decode.success(ZoneFindRow(zone_id:, name:))
  }

  "-- finds a zone
SELECT * FROM template_zones WHERE zone_id = $1"
  |> pog.query
  |> pog.parameter(pog.int(arg_1))
  |> pog.returning(decoder)
  |> pog.execute(db)
}
