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
