//// An assortment of miscellaneous library functions.
//// 

import gleam/bool
import gleam/dict.{type Dict}
import gleam/io
import gleam/list.{Continue, Stop}
import gleam/pair
import gleam/result
import prng/random

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
  case ordinal < 0 {
    // if ordinal is negative, seek in reverse order
    True -> find_nth_loop(list.reverse(list), -ordinal, is_desired)
    // else proceed as normal
    False -> find_nth_loop(list, ordinal, is_desired)
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
        True -> find_nth(in: rest, nth: ordinal - 1, one_that: is_desired)
        False -> find_nth(in: rest, nth: ordinal, one_that: is_desired)
      }
  }
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
pub fn random(list: List(a)) -> a {
  let index = random.int(0, list.length(list) - 1) |> random.random_sample()
  let assert Ok(member) = at(list, index)
  member
}

fn at(list: List(a), index: Int) -> Result(a, Nil) {
  case list {
    [] -> Error(Nil)
    [first, ..] if index < 1 -> Ok(first)
    [_, ..rest] -> at(rest, index - 1)
  }
}

/// Prints with `io.debug` and a provided label.
/// Inspired by Elixir's `IO.inspect()`.
/// 
pub fn debug(term: a, label label: String) {
  io.print(label <> ": ")
  io.debug(term)
}

/// A convenient wrapper around result.map_error() |> result.try().
/// 
pub fn try_map_err(
  result: Result(a, b),
  map_err_with_fun: fn(b) -> e,
  apply_fun: fn(a) -> Result(c, e),
) -> Result(c, e) {
  result.map_error(result, map_err_with_fun)
  |> result.try(apply_fun)
}

/// A convenient wrapper around result.replace_error() |> result.try().
///
pub fn try_replace_err(
  result: Result(a, b),
  replacement: e,
  apply_fun: fn(a) -> Result(b, e),
) -> Result(b, e) {
  result.replace_error(result, replacement)
  |> result.try(apply_fun)
}
