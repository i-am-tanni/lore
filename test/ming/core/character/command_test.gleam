import gleeunit
import gleeunit/should
import ming/character/command

pub fn main() {
  gleeunit.main()
}

pub fn single_command_test() {
  command.pre_parser("NoRtH\r\n")
  |> should.equal(#("north", ""))
}

pub fn command_with_args_test() {
  command.pre_parser("SAY  \tSpeak Friend and Enter.\r\n")
  |> should.equal(#("say", "Speak Friend and Enter.\r\n"))
}
