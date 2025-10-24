//// Parsers and parser primatives useful for parsing commands.
////

import gleam/bool
import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import lore/character/act
import lore/character/conn.{type Conn}
import lore/character/events/item_event
import lore/character/socials
import lore/character/users
import lore/character/view
import lore/character/view/character_view
import lore/character/view/communication_view
import lore/character/view/error_view
import lore/character/view/item_view
import lore/world
import lore/world/event
import lore/world/system_tables
import party.{type Parser, any_char, char, string}

pub type Command(verb, data) {
  Command(verb: verb, data: data)
}

type Prompt {
  Prompt
}

type Verb {
  Look
  Go
  Quit
  Who
  Get
  Drop
  Inventory
}

type DoorVerb {
  Open
  Close
}

type CommunicationVerb {
  Say
  Whisper
  Emote
}

type Channel {
  Chat
}

type Argument {
  Adverb
  At
}

type Found {
  Self
  Item(world.ItemInstance)
}

pub fn parse(conn: Conn, input: String) -> Conn {
  let result = party.go(parser(conn), input)

  case result {
    Ok(conn) -> conn

    Error(error) ->
      conn
      |> conn.renderln(error_view.parse_error(error))
      |> conn.prompt()
  }
}

fn parser(conn: Conn) -> Parser(Conn, e) {
  party.choice([
    command(conn, prompt_command, empty()),
    command(conn, look_command, no_args(Look, "look", ["l"])),
    command(conn, look_at_command, with_args(Look, "look", ["l"], word)),
    command(conn, move_command, go("north", ["n"])),
    command(conn, move_command, go("south", ["s"])),
    command(conn, move_command, go("east", ["e"])),
    command(conn, move_command, go("west", ["w"])),
    command(conn, move_command, go("up", ["u"])),
    command(conn, move_command, go("down", ["d"])),
    command(conn, who_command, no_args(Who, "who", [])),
    command(conn, room_comms, with_args(Say, "say", [], say_args)),
    command(conn, room_comms, with_args(Whisper, "whisper", [], whisper_args)),
    command(conn, room_comms, with_args(Emote, "emote", [], emote_text)),
    command(conn, door_command, with_args(Open, "open", ["op"], direction)),
    command(conn, door_command, with_args(Close, "close", ["cl"], direction)),
    command(conn, chat_command, with_args(Chat, "chat", [], remaining_text)),
    command(conn, get_command, with_args(Get, "get", ["g"], word)),
    command(conn, drop_command, with_args(Drop, "drop", ["dr"], word)),
    command(
      conn,
      inventory_command,
      no_args(Inventory, "inventory", ["i", "inv"]),
    ),
    command(conn, quit_command, no_args(Quit, "quit", ["q"])),
    social(conn),
  ])
}

// An empty command will display the prompt
fn prompt_command(conn: Conn, _: Command(Prompt, Nil)) -> Conn {
  conn.prompt(conn)
}

fn move_command(conn: Conn, command: Command(Verb, world.Direction)) -> Conn {
  conn.action(conn, act.move(command.data))
}

fn look_command(conn: Conn, _: Command(Verb, Nil)) -> Conn {
  conn.event(conn, event.Look)
}

fn look_at_command(conn: Conn, command: Command(Verb, String)) -> Conn {
  let search_term = command.data
  let self = conn.get_character(conn)
  let found_result = {
    use <- bool.guard(
      search_term == "self"
        || list.any(self.keywords, fn(keyword) { search_term == keyword }),
      Ok(Self),
    )
    list.find(self.inventory, fn(item_instance) {
      list.any(item_instance.keywords, fn(keyword) { search_term == keyword })
    })
    |> result.map(Item)
  }

  case found_result {
    Ok(Self) ->
      conn
      |> conn.renderln(character_view.look_at(self))
      |> conn.prompt()

    Ok(Item(item_instance)) -> item_event.look_at(conn, item_instance)

    Error(Nil) -> conn.event(conn, event.LookAt(search_term))
  }
}

fn door_command(conn: Conn, command: Command(DoorVerb, world.Direction)) -> Conn {
  let desired_state = case command.verb {
    Open -> world.Open
    Close -> world.Closed
  }

  let data = event.DoorToggleData(desired_state:, exit_keyword: command.data)

  conn.action(conn, act.toggle_door(data))
}

fn room_comms(
  conn: Conn,
  command: Command(CommunicationVerb, event.RoomCommunicationData),
) {
  let data = command.data
  case data {
    event.SayData(text: "", ..) ->
      conn
      |> conn.renderln(communication_view.empty("say"))
      |> conn.prompt()

    event.SayAtData(text: "", at:, ..) ->
      conn
      |> conn.renderln(communication_view.empty("say to " <> at))
      |> conn.prompt()

    event.WhisperData(text: "", at:, ..) ->
      conn
      |> conn.renderln(communication_view.empty("whisper to " <> at))
      |> conn.prompt()

    event.EmoteData(text: "") ->
      conn
      |> conn.renderln(communication_view.empty("emote"))
      |> conn.prompt()

    _ -> conn.action(conn, act.communicate(data))
  }
}

fn quit_command(conn: Conn, _: Command(Verb, Nil)) -> Conn {
  conn
  |> conn.renderln(character_view.quit())
  |> conn.terminate
}

fn chat_command(conn: Conn, command: Command(Channel, String)) -> Conn {
  let channel = case command.verb {
    Chat -> world.General
  }

  case conn.is_subscribed(conn, channel) {
    True -> conn.publish(conn, channel, command.data)

    False ->
      conn.renderln(conn, communication_view.channel_not_subscribed(channel))
      |> conn.prompt()
  }
}

fn inventory_command(conn: Conn, _command: Command(Verb, Nil)) -> Conn {
  let system_tables.Lookup(items:, ..) = conn.system_tables(conn)
  let character = conn.get_character(conn)

  conn.renderln(conn, item_view.inventory(items, character))
  |> conn.prompt()
}

fn get_command(conn: Conn, command: Command(Verb, String)) -> Conn {
  conn.action(conn, act.item_get(command.data))
}

fn drop_command(conn: Conn, command: Command(Verb, String)) -> Conn {
  let keyword = command.data
  let world.MobileInternal(inventory:, ..) = conn.get_character(conn)
  let result = {
    use item <- list.find(inventory)
    use item_keyword <- list.any(item.keywords)
    keyword == item_keyword
  }

  case result {
    Ok(item_instance) -> conn.action(conn, act.item_drop(item_instance))
    Error(Nil) ->
      conn
      |> conn.renderln(error_view.not_carrying_error())
      |> conn.prompt()
  }
}

fn who_command(conn: Conn, _command: Command(Verb, Nil)) -> Conn {
  let system_tables.Lookup(users:, ..) = conn.system_tables(conn)
  conn.render(conn, character_view.who_list(users.players_logged_in(users)))
}

pub fn social(conn: Conn) -> Parser(Conn, e) {
  use command <- party.do(word())
  use victim <- party.do(party.perhaps(word()))
  let victim = option.from_result(victim)
  let system_tables.Lookup(socials:, ..) = conn.system_tables(conn)
  let self = conn.get_character(conn)
  let is_auto = case victim {
    None -> False
    Some("self") -> True
    Some(search_term) ->
      list.any(self.keywords, fn(keyword) { search_term == keyword })
  }

  case socials.lookup(socials, command), victim {
    Ok(social), None -> {
      let report =
        view.ReportBasic(
          self: social.char_no_arg,
          witness: social.others_no_arg,
        )
      conn.event(conn, event.RoomCommunication(event.SocialData(report)))
      |> party.return
    }

    Ok(social), Some(_) if is_auto -> {
      let report =
        view.ReportBasic(self: social.char_auto, witness: social.others_auto)
      conn.event(conn, event.RoomCommunication(event.SocialData(report)))
      |> party.return
    }

    Ok(social), Some(search_term) -> {
      let report =
        view.ReportAdvanced(
          self: social.char_found,
          witness: social.others_found,
          victim: social.victim_found,
        )
      conn.event(
        conn,
        event.RoomCommunication(event.SocialAtData(report, search_term)),
      )
      |> party.return
    }

    Error(Nil), _ -> party.fail()
  }
}

pub fn command(
  conn: Conn,
  with fun: fn(Conn, Command(a, args)) -> Conn,
  parser parser: Parser(Command(a, args), e),
) -> Parser(Conn, e) {
  use command <- party.do(parser)
  // Note: Can insert a function here to check if character has permission to
  // perform command.
  party.return(fun(conn, command))
}

fn go(
  command: String,
  aliases: List(String),
) -> Parser(Command(Verb, world.Direction), e) {
  use verb <- party.do(party.between(
    whitespace(),
    verb(Go, command, aliases),
    whitespace(),
  ))
  // If parsed, we know direction is valid
  let valid_direction = string_to_direction(command)
  party.return(Command(verb: verb, data: valid_direction))
}

fn say_args() -> Parser(event.RoomCommunicationData, e) {
  use options <- party.do(with_options([at(), adverb()]))
  use <- party.drop(whitespace())
  use text <- party.do(remaining_text())

  let text = string.capitalise(text)
  let at = dict.get(options, At)
  let adverb = dict.get(options, Adverb) |> option.from_result()
  case at {
    Ok(at) -> party.return(event.SayAtData(text:, at:, adverb:))
    Error(Nil) -> party.return(event.SayData(text:, adverb:))
  }
}

fn whisper_args() -> Parser(event.RoomCommunicationData, e) {
  use at <- party.do(party.choice([party.seq(char("@"), word()), word()]))
  use <- party.drop(whitespace())
  use adverb_option <- party.do(party.perhaps(adverb()))
  let adverb = case adverb_option {
    Ok(#(_, adverb)) -> Some(adverb)
    Error(_) -> None
  }
  use text <- party.do(text(end()))
  party.return(event.WhisperData(text:, at:, adverb:))
}

fn emote_text() -> Parser(event.RoomCommunicationData, e) {
  use text <- party.do(text(until: end()))
  party.return(event.EmoteData(text:))
}

fn direction() -> Parser(world.Direction, e) {
  use valid_direction <- party.do(
    party.choice([
      string("north"),
      string("south"),
      string("east"),
      string("west"),
      string("up"),
      string("down"),
      string("n"),
      string("s"),
      string("e"),
      string("w"),
      string("u"),
      string("d"),
    ]),
  )

  party.return(string_to_direction(valid_direction))
}

fn at() -> Parser(#(Argument, String), e) {
  use keyword <- party.do(party.between(char("@"), word(), whitespace()))
  party.return(#(At, keyword))
}

fn adverb() -> Parser(#(Argument, String), e) {
  use adverb <- party.do(party.between(char(">"), word(), whitespace()))
  party.return(#(Adverb, adverb))
}

fn empty() -> Parser(Command(Prompt, Nil), e) {
  use _ <- party.do(party.all([whitespace(), end()]))
  party.return(Command(verb: Prompt, data: Nil))
}

pub fn no_args(
  tag expected_verb: v,
  command command: String,
  aliases aliases: List(String),
) -> Parser(Command(v, Nil), e) {
  use verb <- party.do(party.between(
    whitespace(),
    verb(expected_verb, command, aliases),
    whitespace(),
  ))
  use <- party.drop(party.end())
  party.return(Command(verb: verb, data: Nil))
}

pub fn with_args(
  tag expected_verb: v,
  command command: String,
  aliases verb_aliases: List(String),
  then_parse args_parser: fn() -> Parser(a, e),
) -> Parser(Command(v, a), e) {
  use verb <- party.do(party.between(
    whitespace(),
    verb(expected_verb, command, aliases: verb_aliases),
    whitespace(),
  ))
  use args <- party.do(args_parser())
  use <- party.drop(whitespace())
  use <- party.drop(party.end())
  party.return(Command(verb: verb, data: args))
}

fn verb(
  tag tag: v,
  command command: String,
  aliases aliases: List(String),
) -> Parser(v, error) {
  let aliases = list.map(aliases, fn(alias) { exact_word(alias) })
  use verb <- party.do(word())
  case party.go(party.choice([party.string(command), ..aliases]), verb) {
    Ok(_) -> party.return(tag)
    Error(_) -> party.fail()
  }
}

/// Given a list of parsers that return a key-val pair, returns a dict
/// of options.
///
fn with_options(parsers: List(Parser(#(a, b), e))) -> Parser(Dict(a, b), e) {
  use options <- party.do(party.perhaps(party.many(party.choice(parsers))))
  options
  |> result.unwrap([])
  |> dict.from_list
  |> party.return
}

fn text(until terminator: Parser(a, e)) -> Parser(String, e) {
  party.until(any_char(), terminator)
  |> party.map(string.concat)
}

fn remaining_text() -> Parser(String, e) {
  text(until: end())
}

fn whitespace1() -> Parser(Nil, e) {
  // not sure why removing char("\r\n") breaks this parser
  party.many1(
    party.choice([char(" "), char("\t"), char("\r"), char("\n"), char("\r\n")]),
  )
  |> replace(Nil)
}

// Parse zero or more whitespace characters
fn whitespace() -> Parser(Nil, e) {
  // not sure why removing char("\r\n") breaks this parser
  party.many(
    party.choice([char(" "), char("\t"), char("\r"), char("\n"), char("\r\n")]),
  )
  |> replace(Nil)
}

fn word() -> party.Parser(String, e) {
  use list <- party.do(party.until(
    party.any_char(),
    party.choice([whitespace1(), end()]),
  ))
  case list != [] {
    True -> party.return(list |> string.concat |> string.lowercase)
    False -> party.fail()
  }
}

fn replace(parser: Parser(a, e), replacement: b) -> Parser(b, e) {
  party.map(parser, fn(_) { replacement })
}

fn end() -> Parser(Nil, e) {
  party.choice([
    replace(char("\r\n"), Nil),
    replace(char("\n"), Nil),
    party.end(),
  ])
}

fn exact_word(string: String) -> Parser(String, e) {
  use string <- party.do(party.string(string))
  use <- party.drop(party.choice([party.end(), whitespace1()]))
  party.return(string)
}

fn string_to_direction(exit_keyword: String) -> world.Direction {
  case exit_keyword {
    "n" | "north" -> world.North
    "s" | "south" -> world.South
    "e" | "east" -> world.East
    "w" | "west" -> world.West
    "u" | "up" -> world.Up
    "d" | "down" -> world.Down
    custom -> world.CustomExit(custom)
  }
}
