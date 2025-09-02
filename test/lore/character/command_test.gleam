import gleam/string
import gleeunit/should
import lore/character/command.{Command}
import party

type North {
  North
}

type Say {
  Say
}

pub fn command_no_args_test() {
  let input = "  NOrth   \r\n"
  let parser = command.no_args(North, "north", ["n"])
  let result = party.go(parser, input)
  assert Ok(Command(North, Nil)) == result
}

pub fn command_no_args_fail_test() {
  let input = "l\r\n"
  let parser = command.no_args(North, "north", ["n"])
  let result = party.go(parser, input)
  should.be_error(result)
}

pub fn command_no_args_alias_test() {
  let input = "n\r\n"
  let parser = command.no_args(North, "north", ["n"])
  let result = party.go(parser, input)
  assert Ok(Command(North, Nil)) == result
}

pub fn command_with_args_test() {
  let input = "say Hello World.\r\n"
  let parser = command.with_args(Say, "say", [], text)
  let result = party.go(parser, input)
  assert Ok(Command(verb: Say, data: "Hello World.")) == result
}

fn text() -> party.Parser(String, e) {
  party.until(
    party.any_char(),
    party.choice([
      replace(party.char("\r\n"), Nil),
      replace(party.char("\n"), Nil),
      party.end(),
    ]),
  )
  |> party.map(string.concat)
}

fn replace(parser: party.Parser(a, e), replacement: b) -> party.Parser(b, e) {
  party.map(parser, fn(_) { replacement })
}
