//// This module contains the code to run the sql queries defined in
//// `./src/web_editor/sql`.
//// > 🐿️ This module was generated automatically using v4.4.1 of
//// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
////

import gleam/dynamic/decode
import gleam/option.{type Option}
import pog

/// Runs the `door_deactivate` query
/// defined in `./src/web_editor/sql/door_deactivate.sql`.
///
/// > 🐿️ This function was generated automatically using v4.4.1 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn door_deactivate(
  db: pog.Connection,
  arg_1: Int,
) -> Result(pog.Returned(Nil), pog.QueryError) {
  let decoder = decode.map(decode.dynamic, fn(_) { Nil })

  "UPDATE door
SET is_active = FALSE
WHERE door_id = $1;"
  |> pog.query
  |> pog.parameter(pog.int(arg_1))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `door_get` query
/// defined in `./src/web_editor/sql/door_get.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.4.1 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type DoorGetRow {
  DoorGetRow(door_id: Int, access_state: AccessState)
}

/// Runs the `door_get` query
/// defined in `./src/web_editor/sql/door_get.sql`.
///
/// > 🐿️ This function was generated automatically using v4.4.1 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn door_get(
  db: pog.Connection,
  arg_1: Int,
) -> Result(pog.Returned(DoorGetRow), pog.QueryError) {
  let decoder = {
    use door_id <- decode.field(0, decode.int)
    use access_state <- decode.field(1, access_state_decoder())
    decode.success(DoorGetRow(door_id:, access_state:))
  }

  "SELECT d.door_id, d.access_state FROM door as d
INNER JOIN door_side as s ON s.door_id = d.door_id
INNER JOIN exit as e ON e.exit_id = s.exit_id
INNER JOIN room as r ON r.room_id = e.from_room_id
WHERE r.room_id = $1;
"
  |> pog.query
  |> pog.parameter(pog.int(arg_1))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `door_get_from_exit_id` query
/// defined in `./src/web_editor/sql/door_get_from_exit_id.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.4.1 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type DoorGetFromExitIdRow {
  DoorGetFromExitIdRow(door_id: Int)
}

/// Runs the `door_get_from_exit_id` query
/// defined in `./src/web_editor/sql/door_get_from_exit_id.sql`.
///
/// > 🐿️ This function was generated automatically using v4.4.1 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn door_get_from_exit_id(
  db: pog.Connection,
  arg_1: Int,
) -> Result(pog.Returned(DoorGetFromExitIdRow), pog.QueryError) {
  let decoder = {
    use door_id <- decode.field(0, decode.int)
    decode.success(DoorGetFromExitIdRow(door_id:))
  }

  "SELECT d.door_id FROM door as d
JOIN door_side as s ON s.door_id = d.door_id
WHERE s.exit_id = $1;
"
  |> pog.query
  |> pog.parameter(pog.int(arg_1))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `door_insert` query
/// defined in `./src/web_editor/sql/door_insert.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.4.1 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type DoorInsertRow {
  DoorInsertRow(door_id: Int)
}

/// recycle any inactive ids before inserting a new row
///
/// > 🐿️ This function was generated automatically using v4.4.1 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn door_insert(
  db: pog.Connection,
  arg_1: AccessState,
) -> Result(pog.Returned(DoorInsertRow), pog.QueryError) {
  let decoder = {
    use door_id <- decode.field(0, decode.int)
    decode.success(DoorInsertRow(door_id:))
  }

  "-- recycle any inactive ids before inserting a new row
WITH reused AS (
  UPDATE door
  SET
    access_state = $1,
    is_active = TRUE
  WHERE door_id = (
    SELECT door_id FROM door
    WHERE is_active = FALSE
    LIMIT 1
  )
  RETURNING *
)

-- If nothing was reused, create a new door
INSERT INTO door (access_state, is_active)
SELECT $1, TRUE
WHERE NOT EXISTS (SELECT 1 FROM reused)
RETURNING door_id;
"
  |> pog.query
  |> pog.parameter(access_state_encoder(arg_1))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// Runs the `exit_deactivate` query
/// defined in `./src/web_editor/sql/exit_deactivate.sql`.
///
/// > 🐿️ This function was generated automatically using v4.4.1 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn exit_deactivate(
  db: pog.Connection,
  arg_1: Int,
) -> Result(pog.Returned(Nil), pog.QueryError) {
  let decoder = decode.map(decode.dynamic, fn(_) { Nil })

  "WITH deactivate_exit AS (
  UPDATE exit
  SET is_active = FALSE
  WHERE exit_id = $1
  RETURNING to_room_id
),

-- If exit has a door, deactivate the door and both sides

deactivate_door_side AS (
  UPDATE door_side
  SET is_active = FALSE
  WHERE exit_id = $1
  RETURNING door_id
),

deactivate_door AS (
  UPDATE door
  SET is_active = FALSE
  WHERE door_id = (SELECT door_id FROM deactivate_door_side)
  RETURNING door_id
)

UPDATE door_side
SET is_active = FALSE
WHERE
  exit_id = (SELECT to_room_id FROM deactivate_exit) AND
  door_id = (SELECT door_id FROM deactivate_door)
;
"
  |> pog.query
  |> pog.parameter(pog.int(arg_1))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `exit_get` query
/// defined in `./src/web_editor/sql/exit_get.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.4.1 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type ExitGetRow {
  ExitGetRow(
    exit_id: Int,
    keyword: String,
    from_room_id: Int,
    to_room_id: Int,
    is_active: Bool,
    door_id: Option(Int),
  )
}

/// Runs the `exit_get` query
/// defined in `./src/web_editor/sql/exit_get.sql`.
///
/// > 🐿️ This function was generated automatically using v4.4.1 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn exit_get(
  db: pog.Connection,
  arg_1: Int,
) -> Result(pog.Returned(ExitGetRow), pog.QueryError) {
  let decoder = {
    use exit_id <- decode.field(0, decode.int)
    use keyword <- decode.field(1, decode.string)
    use from_room_id <- decode.field(2, decode.int)
    use to_room_id <- decode.field(3, decode.int)
    use is_active <- decode.field(4, decode.bool)
    use door_id <- decode.field(5, decode.optional(decode.int))
    decode.success(ExitGetRow(
      exit_id:,
      keyword:,
      from_room_id:,
      to_room_id:,
      is_active:,
      door_id:,
    ))
  }

  "SELECT
  e.exit_id,
  e.keyword,
  e.from_room_id,
  e.to_room_id,
  e.is_active,
  d.door_id
FROM exit as e
LEFT JOIN door_side as d
  ON d.exit_id = e.exit_id AND d.is_active
WHERE e.from_room_id = $1 AND e.is_active = TRUE;
"
  |> pog.query
  |> pog.parameter(pog.int(arg_1))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// recycle any inactive ids before inserting a new row
///
/// > 🐿️ This function was generated automatically using v4.4.1 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn exit_insert(
  db: pog.Connection,
  arg_1: Int,
  arg_2: Int,
  arg_3: String,
) -> Result(pog.Returned(Nil), pog.QueryError) {
  let decoder = decode.map(decode.dynamic, fn(_) { Nil })

  "-- recycle any inactive ids before inserting a new row
WITH reused AS (
  UPDATE exit
  SET
    from_room_id = $1,
    to_room_id = $2,
    keyword = $3,
    is_active = TRUE
  WHERE exit_id = (
    SELECT exit_id FROM exit
    WHERE is_active = FALSE
    LIMIT 1
  )
  RETURNING *
)

-- If nothing was reused, create a new exit
INSERT INTO exit (from_room_id, to_room_id, keyword, is_active)
SELECT $1, $2, $3, TRUE
WHERE NOT EXISTS (SELECT 1 FROM reused);
"
  |> pog.query
  |> pog.parameter(pog.int(arg_1))
  |> pog.parameter(pog.int(arg_2))
  |> pog.parameter(pog.text(arg_3))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// recycle any inactive ids before inserting a new row
///
/// > 🐿️ This function was generated automatically using v4.4.1 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn exit_insert_2way(
  db: pog.Connection,
  arg_1: Int,
  arg_2: Int,
  arg_3: String,
  arg_4: String,
) -> Result(pog.Returned(Nil), pog.QueryError) {
  let decoder = decode.map(decode.dynamic, fn(_) { Nil })

  "-- recycle any inactive ids before inserting a new row
WITH reused_forward AS (
  UPDATE exit
  SET
    from_room_id = $1,
    to_room_id = $2,
    keyword = $3,
    is_active = TRUE
  WHERE exit_id = (
    SELECT exit_id FROM exit
    WHERE is_active = FALSE
    LIMIT 1
  )
  RETURNING *
),

reused_reverse AS (
  UPDATE exit
  SET
    from_room_id = $2,
    to_room_id = $1,
    keyword = $4,
    is_active = TRUE
  WHERE exit_id = (
    SELECT exit_id FROM exit
    WHERE is_active = FALSE
    LIMIT 1
  )
  RETURNING *
)

-- If nothing was reused, create new
INSERT INTO exit (from_room_id, to_room_id, keyword, is_active)
SELECT $1, $2, $3, TRUE
WHERE NOT EXISTS (SELECT 1 FROM reused_forward)
UNION
SELECT $2, $1, $4, TRUE
WHERE NOT EXISTS (SELECT 1 FROM reused_reverse)
;
"
  |> pog.query
  |> pog.parameter(pog.int(arg_1))
  |> pog.parameter(pog.int(arg_2))
  |> pog.parameter(pog.text(arg_3))
  |> pog.parameter(pog.text(arg_4))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// recycle any inactive ids before inserting a new row
///
/// > 🐿️ This function was generated automatically using v4.4.1 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn exit_insert_w_door(
  db: pog.Connection,
  arg_1: Int,
  arg_2: Int,
  arg_3: String,
  arg_4: Int,
) -> Result(pog.Returned(Nil), pog.QueryError) {
  let decoder = decode.map(decode.dynamic, fn(_) { Nil })

  "-- recycle any inactive ids before inserting a new row
WITH reused AS (
  UPDATE exit
  SET
    from_room_id = $1,
    to_room_id = $2,
    keyword = $3,
    is_active = TRUE
  WHERE exit_id = (
    SELECT exit_id FROM exit
    WHERE is_active = FALSE
    LIMIT 1
  )
  RETURNING *
),

exit_inserted AS(
  -- If nothing was reused, create a new exit
  INSERT INTO exit (from_room_id, to_room_id, keyword, is_active)
  SELECT $1, $2, $3, TRUE
  WHERE NOT EXISTS (SELECT 1 FROM reused)
  RETURNING exit_id
),

door_side_reused AS (
  UPDATE door_side
  SET
    exit_id = (SELECT exit_id FROM exit_inserted),
    door_id = $4,
    is_active = TRUE
  WHERE door_side_id = (
    SELECT door_side_id FROM door_side
    WHERE is_active = FALSE
    LIMIT 1
  )
  RETURNING door_side_id
)

INSERT INTO door_side (exit_id, door_id)
SELECT exit_id, $4 FROM exit_inserted
WHERE NOT EXISTS (SELECT 1 FROM door_side_reused);
"
  |> pog.query
  |> pog.parameter(pog.int(arg_1))
  |> pog.parameter(pog.int(arg_2))
  |> pog.parameter(pog.text(arg_3))
  |> pog.parameter(pog.int(arg_4))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `item_get` query
/// defined in `./src/web_editor/sql/item_get.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.4.1 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type ItemGetRow {
  ItemGetRow(
    item_id: Int,
    name: String,
    short: String,
    long: String,
    keywords: List(String),
  )
}

/// Runs the `item_get` query
/// defined in `./src/web_editor/sql/item_get.sql`.
///
/// > 🐿️ This function was generated automatically using v4.4.1 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn item_get(
  db: pog.Connection,
  arg_1: Int,
) -> Result(pog.Returned(ItemGetRow), pog.QueryError) {
  let decoder = {
    use item_id <- decode.field(0, decode.int)
    use name <- decode.field(1, decode.string)
    use short <- decode.field(2, decode.string)
    use long <- decode.field(3, decode.string)
    use keywords <- decode.field(4, decode.list(decode.string))
    decode.success(ItemGetRow(item_id:, name:, short:, long:, keywords:))
  }

  "SELECT
    i.item_id,
    i.name,
    i.short,
    i.long,
    ARRAY(
        SELECT k.keyword
        FROM item_keyword AS ik
        INNER JOIN keyword AS k
            ON k.keyword_id = ik.keyword_id
        WHERE ik.item_id = i.item_id
    ) AS keywords
FROM item AS i
WHERE i.item_id = $1;
"
  |> pog.query
  |> pog.parameter(pog.int(arg_1))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `item_insert` query
/// defined in `./src/web_editor/sql/item_insert.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.4.1 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type ItemInsertRow {
  ItemInsertRow(item_id: Int)
}

/// Runs the `item_insert` query
/// defined in `./src/web_editor/sql/item_insert.sql`.
///
/// > 🐿️ This function was generated automatically using v4.4.1 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn item_insert(
  db: pog.Connection,
  arg_1: String,
  arg_2: String,
  arg_3: String,
  arg_4: List(String),
) -> Result(pog.Returned(ItemInsertRow), pog.QueryError) {
  let decoder = {
    use item_id <- decode.field(0, decode.int)
    decode.success(ItemInsertRow(item_id:))
  }

  "WITH inserted_item AS (
    INSERT INTO item (name, short, long)
    VALUES ($1, $2, $3)
    RETURNING item_id
),
inserted_keywords AS (
    INSERT INTO keyword (keyword)
    SELECT unnest($4::text[])
    ON CONFLICT (keyword) DO UPDATE SET keyword = EXCLUDED.keyword
    RETURNING keyword_id
),
link_item_keywords AS (
    INSERT INTO item_keyword (item_id, keyword_id)
    SELECT inserted_item.item_id, inserted_keywords.keyword_id 
    FROM inserted_item, inserted_keywords
    ON CONFLICT (item_id, keyword_id) DO NOTHING
)
SELECT item_id FROM inserted_item;
"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.parameter(pog.text(arg_2))
  |> pog.parameter(pog.text(arg_3))
  |> pog.parameter(pog.array(fn(value) { pog.text(value) }, arg_4))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `item_update` query
/// defined in `./src/web_editor/sql/item_update.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.4.1 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type ItemUpdateRow {
  ItemUpdateRow(item_id: Int)
}

/// Runs the `item_update` query
/// defined in `./src/web_editor/sql/item_update.sql`.
///
/// > 🐿️ This function was generated automatically using v4.4.1 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn item_update(
  db: pog.Connection,
  arg_1: Int,
  arg_2: String,
  arg_3: String,
  arg_4: String,
  arg_5: List(String),
) -> Result(pog.Returned(ItemUpdateRow), pog.QueryError) {
  let decoder = {
    use item_id <- decode.field(0, decode.int)
    decode.success(ItemUpdateRow(item_id:))
  }

  "WITH updated_item AS (
    UPDATE item
    SET name = $2, short = $3, long = $4
    WHERE item_id = $1
    RETURNING item_id AS item_id
),
inserted_keywords AS (
    INSERT INTO keyword (keyword)
    SELECT DISTINCT unnest($5::text[])
    ON CONFLICT (keyword) DO UPDATE SET keyword = EXCLUDED.keyword
    RETURNING keyword_id
),
deleted AS (
    DELETE FROM item_keyword ik
    USING updated_item u
    WHERE ik.item_id = u.item_id
      AND NOT EXISTS (
          SELECT 1
          FROM inserted_keywords k
          WHERE k.keyword_id = ik.keyword_id
      )
),
link_item_keywords AS (
    INSERT INTO item_keyword (item_id, keyword_id)
    SELECT updated_item.item_id, inserted_keywords.keyword_id 
    FROM updated_item, inserted_keywords
    ON CONFLICT (item_id, keyword_id) DO NOTHING
)
SELECT item_id FROM updated_item;

"
  |> pog.query
  |> pog.parameter(pog.int(arg_1))
  |> pog.parameter(pog.text(arg_2))
  |> pog.parameter(pog.text(arg_3))
  |> pog.parameter(pog.text(arg_4))
  |> pog.parameter(pog.array(fn(value) { pog.text(value) }, arg_5))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `mobile_get` query
/// defined in `./src/web_editor/sql/mobile_get.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.4.1 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type MobileGetRow {
  MobileGetRow(
    mobile_id: Int,
    name: String,
    short: String,
    long: Option(String),
    keywords: List(String),
  )
}

/// Runs the `mobile_get` query
/// defined in `./src/web_editor/sql/mobile_get.sql`.
///
/// > 🐿️ This function was generated automatically using v4.4.1 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn mobile_get(
  db: pog.Connection,
  arg_1: Int,
) -> Result(pog.Returned(MobileGetRow), pog.QueryError) {
  let decoder = {
    use mobile_id <- decode.field(0, decode.int)
    use name <- decode.field(1, decode.string)
    use short <- decode.field(2, decode.string)
    use long <- decode.field(3, decode.optional(decode.string))
    use keywords <- decode.field(4, decode.list(decode.string))
    decode.success(MobileGetRow(mobile_id:, name:, short:, long:, keywords:))
  }

  "SELECT
    i.mobile_id,
    i.name,
    i.short,
    i.long,
    ARRAY(
        SELECT k.keyword
        FROM mob_keyword AS ik
        INNER JOIN keyword AS k
            ON k.keyword_id = ik.keyword_id
        WHERE ik.mobile_id = i.mobile_id
    ) AS keywords
FROM mobile AS i
WHERE i.mobile_id = $1;
"
  |> pog.query
  |> pog.parameter(pog.int(arg_1))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `mobile_insert` query
/// defined in `./src/web_editor/sql/mobile_insert.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.4.1 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type MobileInsertRow {
  MobileInsertRow(mobile_id: Int)
}

/// Runs the `mobile_insert` query
/// defined in `./src/web_editor/sql/mobile_insert.sql`.
///
/// > 🐿️ This function was generated automatically using v4.4.1 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn mobile_insert(
  db: pog.Connection,
  arg_1: String,
  arg_2: String,
  arg_3: String,
  arg_4: List(String),
) -> Result(pog.Returned(MobileInsertRow), pog.QueryError) {
  let decoder = {
    use mobile_id <- decode.field(0, decode.int)
    decode.success(MobileInsertRow(mobile_id:))
  }

  "WITH inserted_mobile AS (
    INSERT INTO mobile (name, short, long)
    VALUES ($1, $2, $3)
    RETURNING mobile_id
),
inserted_keywords AS (
    INSERT INTO keyword (keyword)
    SELECT unnest($4::text[])
    ON CONFLICT (keyword) DO UPDATE SET keyword = EXCLUDED.keyword
    RETURNING keyword_id
),
link_mobile_keywords AS (
    INSERT INTO mob_keyword (mobile_id, keyword_id)
    SELECT inserted_mobile.mobile_id, inserted_keywords.keyword_id 
    FROM inserted_mobile, inserted_keywords
    ON CONFLICT (mobile_id, keyword_id) DO NOTHING
)
SELECT mobile_id FROM inserted_mobile;
"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.parameter(pog.text(arg_2))
  |> pog.parameter(pog.text(arg_3))
  |> pog.parameter(pog.array(fn(value) { pog.text(value) }, arg_4))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `mobile_update` query
/// defined in `./src/web_editor/sql/mobile_update.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.4.1 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type MobileUpdateRow {
  MobileUpdateRow(mobile_id: Int)
}

/// Runs the `mobile_update` query
/// defined in `./src/web_editor/sql/mobile_update.sql`.
///
/// > 🐿️ This function was generated automatically using v4.4.1 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn mobile_update(
  db: pog.Connection,
  arg_1: Int,
  arg_2: String,
  arg_3: String,
  arg_4: String,
  arg_5: List(String),
) -> Result(pog.Returned(MobileUpdateRow), pog.QueryError) {
  let decoder = {
    use mobile_id <- decode.field(0, decode.int)
    decode.success(MobileUpdateRow(mobile_id:))
  }

  "WITH updated_mobile AS (
    UPDATE mobile
    SET name = $2, short = $3, long = $4
    WHERE mobile_id = $1
    RETURNING mobile_id AS mobile_id
),
inserted_keywords AS (
    INSERT INTO keyword (keyword)
    SELECT unnest($5::text[])
    ON CONFLICT (keyword) DO UPDATE SET keyword = EXCLUDED.keyword
    RETURNING keyword_id
),
deleted AS (
    DELETE FROM mob_keyword mk
    USING updated_mobile u
    WHERE mk.mobile_id = u.mobile_id
      AND NOT EXISTS (
          SELECT 1
          FROM inserted_keywords k
          WHERE k.keyword_id = mk.keyword_id
      )
),
link_mobile_keywords AS (
    INSERT INTO mob_keyword (mobile_id, keyword_id)
    SELECT updated_mobile.mobile_id, inserted_keywords.keyword_id 
    FROM updated_mobile, inserted_keywords
    ON CONFLICT (mobile_id, keyword_id) DO NOTHING
)
SELECT mobile_id FROM updated_mobile;

"
  |> pog.query
  |> pog.parameter(pog.int(arg_1))
  |> pog.parameter(pog.text(arg_2))
  |> pog.parameter(pog.text(arg_3))
  |> pog.parameter(pog.text(arg_4))
  |> pog.parameter(pog.array(fn(value) { pog.text(value) }, arg_5))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `room_get` query
/// defined in `./src/web_editor/sql/room_get.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.4.1 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type RoomGetRow {
  RoomGetRow(
    room_id: Int,
    name: String,
    zone_id: Int,
    symbol: String,
    x: Int,
    y: Int,
    z: Int,
    description: String,
    zone_name: String,
  )
}

/// Runs the `room_get` query
/// defined in `./src/web_editor/sql/room_get.sql`.
///
/// > 🐿️ This function was generated automatically using v4.4.1 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn room_get(
  db: pog.Connection,
  arg_1: Int,
) -> Result(pog.Returned(RoomGetRow), pog.QueryError) {
  let decoder = {
    use room_id <- decode.field(0, decode.int)
    use name <- decode.field(1, decode.string)
    use zone_id <- decode.field(2, decode.int)
    use symbol <- decode.field(3, decode.string)
    use x <- decode.field(4, decode.int)
    use y <- decode.field(5, decode.int)
    use z <- decode.field(6, decode.int)
    use description <- decode.field(7, decode.string)
    use zone_name <- decode.field(8, decode.string)
    decode.success(RoomGetRow(
      room_id:,
      name:,
      zone_id:,
      symbol:,
      x:,
      y:,
      z:,
      description:,
      zone_name:,
    ))
  }

  "SELECT 
  r.room_id, 
  r.name, 
  r.zone_id, 
  r.symbol, 
  r.x, 
  r.y, 
  r.z, 
  r.description,
  z.name as zone_name
FROM room as r
INNER JOIN zone as z 
ON r.zone_id = z.zone_id
WHERE r.room_id = $1;"
  |> pog.query
  |> pog.parameter(pog.int(arg_1))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `room_insert` query
/// defined in `./src/web_editor/sql/room_insert.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.4.1 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type RoomInsertRow {
  RoomInsertRow(room_id: Int)
}

/// Runs the `room_insert` query
/// defined in `./src/web_editor/sql/room_insert.sql`.
///
/// > 🐿️ This function was generated automatically using v4.4.1 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn room_insert(
  db: pog.Connection,
  arg_1: Int,
  arg_2: String,
  arg_3: String,
  arg_4: String,
  arg_5: Int,
  arg_6: Int,
  arg_7: Int,
) -> Result(pog.Returned(RoomInsertRow), pog.QueryError) {
  let decoder = {
    use room_id <- decode.field(0, decode.int)
    decode.success(RoomInsertRow(room_id:))
  }

  "INSERT INTO room (zone_id, name, description, symbol, x, y, z)
VALUES ($1, $2, $3, $4, $5, $6, $7)
RETURNING room_id;"
  |> pog.query
  |> pog.parameter(pog.int(arg_1))
  |> pog.parameter(pog.text(arg_2))
  |> pog.parameter(pog.text(arg_3))
  |> pog.parameter(pog.text(arg_4))
  |> pog.parameter(pog.int(arg_5))
  |> pog.parameter(pog.int(arg_6))
  |> pog.parameter(pog.int(arg_7))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// Runs the `room_update` query
/// defined in `./src/web_editor/sql/room_update.sql`.
///
/// > 🐿️ This function was generated automatically using v4.4.1 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn room_update(
  db: pog.Connection,
  arg_1: Int,
  arg_2: Int,
  arg_3: String,
  arg_4: String,
  arg_5: String,
  arg_6: Int,
  arg_7: Int,
  arg_8: Int,
) -> Result(pog.Returned(Nil), pog.QueryError) {
  let decoder = decode.map(decode.dynamic, fn(_) { Nil })

  "UPDATE room
SET zone_id=$2, name=$3, description=$4, symbol=$5, x=$6, y=$7, z=$8
WHERE room_id = $1"
  |> pog.query
  |> pog.parameter(pog.int(arg_1))
  |> pog.parameter(pog.int(arg_2))
  |> pog.parameter(pog.text(arg_3))
  |> pog.parameter(pog.text(arg_4))
  |> pog.parameter(pog.text(arg_5))
  |> pog.parameter(pog.int(arg_6))
  |> pog.parameter(pog.int(arg_7))
  |> pog.parameter(pog.int(arg_8))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `zone_get` query
/// defined in `./src/web_editor/sql/zone_get.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.4.1 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type ZoneGetRow {
  ZoneGetRow(zone_id: Int, name: String)
}

/// Runs the `zone_get` query
/// defined in `./src/web_editor/sql/zone_get.sql`.
///
/// > 🐿️ This function was generated automatically using v4.4.1 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn zone_get(
  db: pog.Connection,
  arg_1: Int,
) -> Result(pog.Returned(ZoneGetRow), pog.QueryError) {
  let decoder = {
    use zone_id <- decode.field(0, decode.int)
    use name <- decode.field(1, decode.string)
    decode.success(ZoneGetRow(zone_id:, name:))
  }

  "SELECT 
  zone_id, 
  name 
FROM zone
WHERE zone_id = $1;"
  |> pog.query
  |> pog.parameter(pog.int(arg_1))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `zone_rooms_get` query
/// defined in `./src/web_editor/sql/zone_rooms_get.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.4.1 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type ZoneRoomsGetRow {
  ZoneRoomsGetRow(room_id: Int, name: String)
}

/// Runs the `zone_rooms_get` query
/// defined in `./src/web_editor/sql/zone_rooms_get.sql`.
///
/// > 🐿️ This function was generated automatically using v4.4.1 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn zone_rooms_get(
  db: pog.Connection,
  arg_1: Int,
) -> Result(pog.Returned(ZoneRoomsGetRow), pog.QueryError) {
  let decoder = {
    use room_id <- decode.field(0, decode.int)
    use name <- decode.field(1, decode.string)
    decode.success(ZoneRoomsGetRow(room_id:, name:))
  }

  "SELECT room_id, name FROM room
WHERE zone_id = $1
ORDER BY room_id;"
  |> pog.query
  |> pog.parameter(pog.int(arg_1))
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

fn access_state_encoder(access_state) -> pog.Value {
  case access_state {
    Open -> "open"
    Closed -> "closed"
  }
  |> pog.text
}
