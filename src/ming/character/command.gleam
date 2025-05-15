//// Parsers and parser primatives useful for parsing commands.
//// 

import gleam/bit_array
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import party.{type Parser, alphanum, any_char, char, choice, string}

pub type Command(v, a) {
  Command(verb: v, arguments: Option(a))
}

/// Returns a tuple string pair where the first element is the lowercased
/// command verb and the second are any arguments.
/// 
pub fn pre_parser(s: String) -> #(String, String) {
  pre_parser_loop(bit_array.from_string(s), "", [])
}

fn pre_parser_loop(
  s: BitArray,
  verb: String,
  acc: List(UtfCodepoint),
) -> #(String, String) {
  case s {
    <<>> -> {
      let verb =
        list.reverse(acc)
        |> string.from_utf_codepoints()
        |> string.lowercase()

      #(verb, "")
    }

    <<"\t":utf8, rest:bits>> | <<" ":utf8, rest:bits>> -> {
      let verb =
        list.reverse(acc)
        |> string.from_utf_codepoints()
        |> string.lowercase()

      let assert Ok(rest) =
        rest
        |> remove_leading_whitespace()
        |> bit_array.to_string()

      #(verb, rest)
    }

    <<"\r":utf8, rest:bits>> | <<"\n":utf8, rest:bits>> ->
      // ignore these characters
      pre_parser_loop(rest, verb, acc)

    <<cp:utf8_codepoint, rest:bits>> -> pre_parser_loop(rest, verb, [cp, ..acc])

    _ -> panic as "Impossible"
  }
}

fn remove_leading_whitespace(s: BitArray) -> BitArray {
  case s {
    <<" ":utf8, rest:bits>>
    | <<"\r":utf8, rest:bits>>
    | <<"\n":utf8, rest:bits>>
    | <<"\t":utf8, rest:bits>> -> remove_leading_whitespace(rest)
    _ -> s
  }
}

pub fn command_no_args(
  tag expected_verb: v,
  command command: String,
  aliases aliases: List(String),
) -> Parser(Command(v, a), e) {
  use verb <- party.do(verb(expected_verb, command, aliases))
  party.return(Command(verb: verb, arguments: None))
}

pub fn command_with_args(
  tag expected_verb: v,
  command command: String,
  aliases verb_aliases: List(String),
  then_parse arg_parser: fn() -> Parser(a, e),
) -> Parser(Command(v, a), e) {
  use verb <- party.do(verb(expected_verb, command, aliases: verb_aliases))
  use args <- party.do(arg_parser())
  party.return(Command(verb: verb, arguments: Some(args)))
}

fn verb(
  tag verb: v,
  command command: String,
  aliases aliases: List(String),
) -> Parser(v, e) {
  party.satisfy(fn(s) { list.contains(aliases, s) || s == command })
  |> tag(verb)
}

pub fn downcased_word() -> Parser(String, e) {
  party.until(any_char(), whitespace1())
  |> party.map(string.concat)
  |> party.map(string.lowercase)
}

pub fn text(until terminator: Parser(String, e)) -> Parser(String, e) {
  party.until(any_char(), terminator)
  |> party.map(string.concat)
}

fn tag(parser: Parser(String, e), tag: a) -> Parser(a, e) {
  use _ <- party.map(parser)
  tag
}

fn whitespace1() {
  // not sure why removed char("\r\n") breaks this parser
  party.many1_concat(
    party.choice([char(" "), char("\t"), char("\r"), char("\n"), char("\r\n")]),
  )
}
