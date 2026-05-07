import gleam/dict.{type Dict}

pub type Iterator(k, v)

pub fn find_nth(
  dict: Dict(k, v),
  ordinal: Int,
  one_that_is_desired: fn(k, v) -> Bool,
) -> Result(#(k, v), Nil) {
  find_nth_loop(to_iterator(dict), ordinal, one_that_is_desired)
}

fn find_nth_loop(
  iterator: Iterator(k, v),
  ordinal: Int,
  one_that_is_desired: fn(k, v) -> Bool,
) -> Result(#(k, v), Nil) {
  echo "ok"
  case next(iterator) {
    Ok(#(key, val, next_iterator)) -> {
      case one_that_is_desired(key, val) {
        True if ordinal <= 1 -> Ok(#(key, val))
        True -> find_nth_loop(next_iterator, ordinal - 1, one_that_is_desired)
        False -> find_nth_loop(next_iterator, ordinal, one_that_is_desired)
      }
    }

    Error(Nil) -> Error(Nil)
  }
}

@external(erlang, "maps", "iterator")
fn to_iterator(dict: Dict(k, v)) -> Iterator(k, v)

@external(erlang, "lore_ffi", "maps_safe_next")
fn next(iterator: Iterator(k, v)) -> Result(#(k, v, Iterator(k, v)), Nil)
