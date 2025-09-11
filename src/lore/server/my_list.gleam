//// An assortment of extra list functions.
//// 

import gleam/bool
import gleam/dict.{type Dict}
import gleam/list.{Continue, Stop}
import gleam/pair

/// Returns the nth match in the list.
/// Like the `gleam/list` function `find`, but allows you to elect a match 
/// other than the first.
/// If a negative ordinal is provided, the match is found in reverse order.
/// 
/// ## Example
/// 
/// ```gleam
/// type Person{
///   Teacher(name: String)
///   Student(name: String)
/// }
/// 
/// [Teacher("Sue"), Student("Bob"), Teacher("Beth")]
/// |> find_nth(2, fn(x){
///   case x {
///     Teacher(..) -> True
///     _ -> False
///   }
/// })
/// // -> Ok(Teacher(name: "Beth"))
/// ```
/// 
pub fn find_nth(
  in list: List(a),
  nth ordinal: Int,
  one_that is_desired: fn(a) -> Bool,
) -> Result(a, Nil) {
  case ordinal > 0 {
    True -> find_nth_loop(list, ordinal, is_desired)
    // If order is negative, reverse the list and seek bottom to top
    False -> find_nth_loop(list.reverse(list), -ordinal, is_desired)
  }
}

fn find_nth_loop(
  in list: List(a),
  nth ordinal: Int,
  one_that is_desired: fn(a) -> Bool,
) -> Result(a, Nil) {
  case list {
    [] -> Error(Nil)
    [x, ..rest] ->
      case is_desired(x) {
        True if ordinal <= 1 -> Ok(x)
        True -> find_nth_loop(in: rest, nth: ordinal - 1, one_that: is_desired)
        False -> find_nth_loop(in: rest, nth: ordinal, one_that: is_desired)
      }
  }
}

pub fn find_amount(
  in list: List(a),
  up_to num_elements: Int,
  one_that is_desired: fn(a) -> Bool,
) -> List(a) {
  list
  |> list.filter(is_desired)
  |> list.take(num_elements)
}

/// Returns the result of a find that matches the most keywords.
/// 
pub fn find_with_most_keywords(
  in list: List(a),
  with keywords: List(String),
  that_satisfies match_fun: fn(a, String) -> Bool,
) -> Result(a, Nil) {
  let perfect_score = list.length(keywords)

  // this is basically a list.max_until() that early returns on a perfect score
  list.fold_until(list, #(0, Error(Nil)), fn(acc, x) {
    let score = list.count(keywords, match_fun(x, _))
    // eary return on a perfect score
    use <- bool.lazy_guard(score == perfect_score, fn() {
      Stop(#(perfect_score, Ok(x)))
    })
    // else...
    case score > pair.first(acc) {
      // ...if a better match is found, add to the accumulator
      True -> Continue(#(score, Ok(x)))
      // ...or keep seeking a better match
      False -> Continue(acc)
    }
  })
  |> pair.second
}

/// Choose a random member of the list.
/// 
pub fn random(list: List(a)) -> Result(a, Nil) {
  list.shuffle(list)
  |> list.first
}

/// Get member at the given index
/// 
pub fn at(list: List(a), index: Int) -> Result(a, Nil) {
  case list {
    [] -> Error(Nil)
    [first, ..] if index < 1 -> Ok(first)
    [_, ..rest] -> at(rest, index - 1)
  }
}

// Groups items in the list.
// Similar to `list.group`, but the values are mapped.
// Note: the lists are reversed.
// 
pub fn group_by(list: List(a), group_fun: fn(a) -> #(k, v)) -> Dict(k, List(v)) {
  list.fold(list, dict.new(), fn(acc, x) {
    let #(key, val) = group_fun(x)
    case dict.get(acc, key) {
      Ok(list) -> dict.insert(acc, key, [val, ..list])
      Error(Nil) -> dict.insert(acc, key, [val])
    }
  })
}
