import gleam/bool
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import lore/character/act
import lore/character/conn.{type Conn}
import lore/character/events
import lore/character/users
import lore/character/view/character_view
import lore/character/view/communication_view
import lore/character/view/error_view
import lore/character/view/item_view
import lore/world
import lore/world/event
import lore/world/system_tables
import splitter.{type Splitter}

type Command(a) {
  Command(verb: Verb, data: a)
}

type Verb {
  Look
  Say
  Whisper
  Emote
  Open
  Close
  Chat
  Get
  Drop
  Kill
  Inventory
}

type LookAt {
  Self
  Item(world.ItemInstance)
}

pub fn parse(conn: Conn, input: String) -> Conn {
  let word = splitter.new([" ", "\r\n", "\n"])
  let #(verb, _, rest) = splitter.split(word, input)
  let rest = string.trim_start(rest)
  case string.lowercase(verb) {
    "n" | "north" -> move_command(conn, world.North)
    "s" | "south" -> move_command(conn, world.South)
    "e" | "east" -> move_command(conn, world.East)
    "w" | "west" -> move_command(conn, world.West)
    "u" | "up" -> move_command(conn, world.Up)
    "d" | "down" -> move_command(conn, world.Down)
    "l" | "look" if rest == "" -> command_nil(conn, Look, look_command)
    "l" | "look" -> command(conn, look_at_command, look_at_args(rest, word))
    "say" -> command(conn, room_comms, say_args(rest, word))
    "whisper" -> command(conn, room_comms, whisper_args(rest, word))
    "emote" -> command(conn, room_comms, emote_text(rest))
    "k" | "kill" -> command(conn, kill_command, kill_args(rest, word))
    "op" | "open" ->
      command(conn, door_command, door_args(world.Open, rest, word))
    "cl" | "close" ->
      command(conn, door_command, door_args(world.Closed, rest, word))
    "chat" -> command(conn, chat_command, chat_args(world.General, rest))
    "g" | "get" -> command(conn, get_command, get_args(rest, word))
    "dr" | "drop" -> command(conn, drop_command, drop_args(rest, word))
    "who" -> who_command(conn)
    "quit" -> quit_command(conn)
    "i" | "inventory" -> command_nil(conn, Inventory, inventory_command)
    "" -> conn.prompt(conn)
    _ -> conn
  }
}

fn command(
  conn: Conn,
  command_fun: fn(Conn, data) -> Conn,
  args_result: Result(data, String),
) -> Conn {
  case args_result {
    Ok(data) -> command_fun(conn, data)
    Error(error) -> conn.renderln(conn, error_view.render_error(error))
  }
}

fn command_nil(
  conn: Conn,
  verb: Verb,
  command_fun: fn(Conn, Command(Nil)) -> Conn,
) -> Conn {
  command_fun(conn, Command(verb, Nil))
}

fn look_at_args(s: String, word: Splitter) -> Result(Command(String), String) {
  case keyword(s, word) {
    Ok(#(keyword, _)) -> Ok(Command(Look, keyword))
    Error(_) -> Error("What do you want to look at?")
  }
}

fn say_args(
  s: String,
  word: Splitter,
) -> Result(Command(event.RoomCommunicationData), String) {
  let #(options, s) =
    options(s, [#("at", at(_, word)), #("adverb", adverb(_, word))])

  let text = quote(s)
  let at = list.key_find(options, "at")
  let adverb = list.key_find(options, "adverb") |> option.from_result
  case at {
    Ok(at) -> Command(Say, event.SayAtData(text:, at:, adverb:)) |> Ok
    Error(_) -> Command(Say, event.SayData(text:, adverb:)) |> Ok
  }
}

fn whisper_args(
  s: String,
  word: Splitter,
) -> Result(Command(event.RoomCommunicationData), String) {
  let #(options, s) =
    options(s, [#("at", at(_, word)), #("adverb", adverb(_, word))])
  let text = quote(s)
  let at = list.key_find(options, "at")
  let adverb = list.key_find(options, "adverb") |> option.from_result
  case at {
    Ok(at) -> Command(Whisper, event.WhisperData(text:, at:, adverb:)) |> Ok
    Error(_) -> Error("Who do you want to whisper to?")
  }
}

fn emote_text(s: String) -> Result(Command(event.RoomCommunicationData), String) {
  Ok(Command(Emote, event.EmoteData(text: quote(s))))
}

fn door_args(
  desired_state: world.AccessState,
  s: String,
  word: Splitter,
) -> Result(Command(event.DoorToggleData), String) {
  let #(word, _, _rest) = splitter.split(word, s)
  let verb = case desired_state {
    world.Closed -> Close
    world.Open -> Open
  }

  case string_to_direction(word) {
    world.CustomExit(_) -> Error("Invalid direction.")
    direction -> {
      event.DoorToggleData(desired_state:, exit_keyword: direction)
      |> Command(verb, _)
      |> Ok
    }
  }
}

fn chat_args(
  channel: world.ChatChannel,
  s: String,
) -> Result(Command(#(world.ChatChannel, String)), String) {
  let text = quote(s)
  case text != "" {
    True -> Ok(Command(Chat, #(channel, text)))
    False -> Error("What message do you want to send?")
  }
}

fn get_args(s: String, word: Splitter) -> Result(Command(String), String) {
  case keyword(s, word) {
    Ok(#(keyword, _)) -> Ok(Command(Get, keyword))
    Error(_) -> Error("What do you want to get?")
  }
}

fn drop_args(s: String, word: Splitter) -> Result(Command(String), String) {
  case keyword(s, word) {
    Ok(#(keyword, _)) -> Ok(Command(Drop, keyword))
    Error(_) -> Error("What do you want to drop?")
  }
}

fn kill_args(s: String, word: Splitter) -> Result(Command(String), String) {
  case keyword(s, word) {
    Ok(#(keyword, _)) -> Ok(Command(Kill, keyword))
    Error(_) -> Error("What do you want to kill?")
  }
}

fn quote(s: String) -> String {
  let #(text, _) = splitter.new(["\r\n", "\n"]) |> splitter.split_before(s)
  string.capitalise(text)
}

fn keyword(s: String, word: Splitter) -> Result(#(String, String), Nil) {
  let #(keyword, _, rest) = splitter.split(word, s)
  case keyword != "" {
    True -> Ok(#(keyword, string.trim_start(rest)))
    False -> Error(Nil)
  }
}

// Parsers is a list of #(tag, option_parser_fun)
// The output is a tuple containing a key_val list of options found
// and the rest of the unconsumed string
//
fn options(
  s: String,
  parsers: List(#(String, fn(String) -> Result(#(String, String), Nil))),
) -> #(List(#(String, String)), String) {
  options_loop(s, parsers, [], [])
}

fn options_loop(
  s: String,
  parsers: List(#(String, fn(String) -> Result(#(String, String), Nil))),
  to_try_again: List(#(String, fn(String) -> Result(#(String, String), Nil))),
  acc: List(#(String, String)),
) -> #(List(#(String, String)), String) {
  // Any failed parsers will be stashed in to_try_again in case the failure
  // is due to option order
  case parsers {
    [] -> #(acc, s)
    [#(tag, parser_fun) as parser, ..rest] ->
      case parser_fun(s) {
        Ok(#(option, s)) if to_try_again == [] ->
          options_loop(s, rest, [], [#(tag, option), ..acc])

        Ok(#(option, s)) ->
          options_loop(s, list.append(rest, to_try_again), [], [
            #(tag, option),
            ..acc
          ])

        // since options could be in any order, try again later if there is
        // ever a success
        Error(Nil) -> options_loop(s, rest, [parser, ..to_try_again], acc)
      }
  }
}

fn at(s: String, word: Splitter) -> Result(#(String, String), Nil) {
  let #(slice, _, rest) = splitter.split(word, s)
  let rest = string.trim_start(rest)
  case slice {
    "@" <> keyword -> Ok(#(keyword, rest))
    "at" -> keyword(rest, word)
    _ -> Error(Nil)
  }
}

fn adverb(s: String, word: Splitter) -> Result(#(String, String), Nil) {
  let #(slice, _, rest) = splitter.split(word, s)
  let rest = string.trim_start(rest)
  case slice {
    ">" <> adverb -> Ok(#(adverb, rest))
    _ -> Error(Nil)
  }
}

//
// Command Functions
//

fn move_command(conn: Conn, direction: world.Direction) -> Conn {
  conn.action(conn, act.move(direction))
}

fn look_command(conn: Conn, _: Command(Nil)) -> Conn {
  conn.event(conn, event.Look)
}

fn look_at_command(conn: Conn, command: Command(String)) -> Conn {
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

    Ok(Item(item_instance)) -> events.item_look_at(conn, item_instance)

    Error(Nil) -> conn.event(conn, event.LookAt(search_term))
  }
}

fn room_comms(conn: Conn, command: Command(event.RoomCommunicationData)) {
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

fn door_command(conn: Conn, command: Command(event.DoorToggleData)) -> Conn {
  conn.action(conn, act.toggle_door(command.data))
}

fn chat_command(
  conn: Conn,
  command: Command(#(world.ChatChannel, String)),
) -> Conn {
  let #(channel, message) = command.data

  case conn.is_subscribed(conn, channel) {
    True -> conn.publish(conn, channel, message)

    False ->
      conn.renderln(conn, communication_view.channel_not_subscribed(channel))
      |> conn.prompt()
  }
}

fn get_command(conn: Conn, command: Command(String)) -> Conn {
  conn.action(conn, act.item_get(command.data))
}

fn drop_command(conn: Conn, command: Command(String)) -> Conn {
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

fn kill_command(conn: Conn, command: Command(String)) -> Conn {
  let self = conn.get_character(conn)
  let search_term = command.data
  let is_auto = case search_term {
    "self" -> True
    search_term ->
      list.any(self.keywords, fn(keyword) { search_term == keyword })
  }

  case !is_auto {
    True ->
      event.CombatRequestData(
        victim: event.Keyword(command.data),
        dam_roll: world.random(8),
        is_round_based: False,
      )
      |> act.kill
      |> conn.action(conn, _)

    False ->
      conn
      |> conn.renderln(error_view.cannot_target_self())
      |> conn.prompt()
  }
}

fn inventory_command(conn: Conn, _command: Command(Nil)) -> Conn {
  let system_tables.Lookup(items:, ..) = conn.system_tables(conn)
  let character = conn.get_character(conn)

  conn.renderln(conn, item_view.inventory(items, character))
  |> conn.prompt()
}

fn who_command(conn: Conn) -> Conn {
  let system_tables.Lookup(users:, ..) = conn.system_tables(conn)
  conn.render(conn, character_view.who_list(users.players_logged_in(users)))
}

fn quit_command(conn: Conn) -> Conn {
  conn
  |> conn.renderln(character_view.quit())
  |> conn.terminate
}

//
// Helper Functions
//
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
