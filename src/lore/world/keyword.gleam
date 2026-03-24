//// This is basically an overengineered solution for keyword comparison where
//// instead of keyword strings living on 'objects', we store keyword ids as
//// ints.
////
//// Step 1:
//// When a keyword search is performed, the keyword is hashed and
//// compared to known hashes from the database cached in this actor.
//// If a match is found, return a keyword_id and continue.
////
//// Step 2:
//// A keyword_id is returned, which is then compared to keyword_ids on items,
//// mobiles, etc.
////
//// If a match is NOT found, the search automatically fails before
//// moving to step 2
////
//// This has two advantages:
//// 1. Interactables can more efficiently store keywords as ids, making deep
//// copies less expensive to pass around in messages.
//// 2. We can short circuit the search if no known hash is found
////
//// ## Mispellings
////
//// Mispellings will never succeed. This trades speed and correctness for
//// helpfulness. We could however offer some suggestions given context:
////
//// In the case of failure, we can collect a list of keyword_ids
//// and send to this actor to be mapped to keyword strings for jaro distance
//// comparison. We could do this in two short circuiting steps: once for
//// private state comparison and another for room state comparison.
////
//// However, this would not help for keywords the builder
//// failed to consider!
////

import gleam/dict.{type Dict}
import gleam/erlang/process
import gleam/list
import gleam/otp/actor
import gleam/result
import logging
import lore/server/my_list
import lore/world/sql
import pog

pub type Keyword {
  Keyword(id: Int, term: String)
}

/// Information for a keyword search returning one match considering order
///
pub type OrdinalSearch {
  OrdinalSearch(keyword: Keyword, ordinal: Int)
}

/// Information for a keyword search returning a list of matches
/// not exceeding quantity
///
pub type QuantitySearch {
  QuantitySearch(keyword: Keyword, quantity: Int)
}

pub type Message {
  Lookup(caller: process.Subject(Result(Int, Nil)), keyword: String)
}

type HashData {
  Perfect(Keyword)
  Collisions(List(Keyword))
}

type State {
  State(lookup: Dict(Int, HashData))
}

pub fn start(
  actor_name: process.Name(Message),
  db: process.Name(pog.Message),
) -> Result(actor.Started(process.Subject(Message)), actor.StartError) {
  logging.log(logging.Info, "Starting Keyword cache")

  actor.new_with_initialiser(500, fn(self) { init(self, actor_name, db) })
  |> actor.named(actor_name)
  |> actor.on_message(recv)
  |> actor.start
}

fn init(
  self: process.Subject(Message),
  _actor_name: process.Name(Message),
  db: process.Name(pog.Message),
) -> Result(actor.Initialised(State, Message, process.Subject(Message)), String) {
  let db = pog.named_connection(db)
  use pog.Returned(rows: keyword_rows, ..) <- result.try(
    sql.keyword(db)
    |> result.replace_error("Could not get keywords from the database!"),
  )

  let lookup =
    list.fold(keyword_rows, dict.new(), fn(acc, row) {
      let sql.KeywordRow(keyword_id:, keyword:) = row
      insert(acc, hash(keyword), Keyword(id: keyword_id, term: keyword))
    })

  State(lookup:)
  |> actor.initialised
  |> actor.returning(self)
  |> Ok
}

pub fn from_term(
  actor_name: process.Name(Message),
  term: String,
) -> Result(Keyword, Nil) {
  to_id(actor_name, term)
  |> result.map(Keyword(_, term:))
}

/// a synchronous call to the keyword cache to attempt a keyword_id conversion
///
pub fn to_id(
  actor_name: process.Name(Message),
  keyword: String,
) -> Result(Int, Nil) {
  process.named_subject(actor_name)
  |> actor.call(1000, Lookup(caller: _, keyword:))
}

pub fn find(
  list: List(a),
  seek: OrdinalSearch,
  predicate: fn(a, Int) -> Bool,
) -> Result(a, Nil) {
  my_list.find_nth(list, seek.ordinal, predicate(_, seek.keyword.id))
}

pub fn filter_take(
  list: List(a),
  seek: QuantitySearch,
  predicate: fn(a, Int) -> Bool,
) -> List(a) {
  my_list.filter_take(list, seek.quantity, predicate(_, seek.keyword.id))
}

fn recv(state: State, msg: Message) -> actor.Next(State, Message) {
  let Lookup(caller:, keyword:) = msg
  actor.send(caller, lookup(state.lookup, keyword))
  actor.continue(state)
}

fn lookup(lookup: Dict(Int, HashData), input: String) -> Result(Int, Nil) {
  use match <- result.try(dict.get(lookup, hash(input)))
  case match {
    // If a single match is found, assume correct because garbage input that
    // matches a perfect hash in the table is unlikely to succeed when
    // compared against the keyword ids on the thing.
    //
    // If there is a problematic collision, we can simply add the exception case
    // to the table.
    Perfect(Keyword(id:, ..)) -> Ok(id)
    // .. else if there are collisions, we must resolve via string comparison
    Collisions(collisions) ->
      list.find_map(collisions, fn(keyword_data) {
        case keyword_data {
          Keyword(id:, term:) if term == input -> Ok(id)
          _ -> Error(Nil)
        }
      })
  }
}

fn insert(
  lookup: Dict(Int, HashData),
  hash: Int,
  keyword_data: Keyword,
) -> Dict(Int, HashData) {
  let value = case dict.get(lookup, hash) {
    Error(Nil) -> Perfect(keyword_data)
    Ok(Perfect(first_match)) -> Collisions([keyword_data, first_match])
    Ok(Collisions(collisions)) -> Collisions([keyword_data, ..collisions])
  }
  dict.insert(lookup, hash, value)
}

@external(erlang, "erlang", "phash2")
fn hash(term: String) -> Int
