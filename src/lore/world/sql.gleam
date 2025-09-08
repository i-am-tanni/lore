//// This module contains the code to run the sql queries defined in
//// `./src/lore/world/sql`.
//// > 🐿️ This module was generated automatically using v4.4.1 of
//// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
////

import gleam/dynamic/decode
import pog

/// A row you get from running the `items_get` query
/// defined in `./src/lore/world/sql/items_get.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.4.1 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type ItemsGetRow {
  ItemsGetRow(
    item_id: Int,
    name: String,
    short: String,
    long: String,
    keywords: List(String),
  )
}

/// Runs the `items_get` query
/// defined in `./src/lore/world/sql/items_get.sql`.
///
/// > 🐿️ This function was generated automatically using v4.4.1 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn items_get(
  db: pog.Connection,
) -> Result(pog.Returned(ItemsGetRow), pog.QueryError) {
  let decoder = {
    use item_id <- decode.field(0, decode.int)
    use name <- decode.field(1, decode.string)
    use short <- decode.field(2, decode.string)
    use long <- decode.field(3, decode.string)
    use keywords <- decode.field(4, decode.list(decode.string))
    decode.success(ItemsGetRow(item_id:, name:, short:, long:, keywords:))
  }

  "SELECT * from item;"
  |> pog.query
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `socials_get` query
/// defined in `./src/lore/world/sql/socials_get.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.4.1 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type SocialsGetRow {
  SocialsGetRow(
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

/// Runs the `socials_get` query
/// defined in `./src/lore/world/sql/socials_get.sql`.
///
/// > 🐿️ This function was generated automatically using v4.4.1 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn socials_get(
  db: pog.Connection,
) -> Result(pog.Returned(SocialsGetRow), pog.QueryError) {
  let decoder = {
    use command <- decode.field(0, decode.string)
    use char_auto <- decode.field(1, decode.string)
    use char_no_arg <- decode.field(2, decode.string)
    use char_found <- decode.field(3, decode.string)
    use others_auto <- decode.field(4, decode.string)
    use others_found <- decode.field(5, decode.string)
    use others_no_arg <- decode.field(6, decode.string)
    use vict_found <- decode.field(7, decode.string)
    decode.success(SocialsGetRow(
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
