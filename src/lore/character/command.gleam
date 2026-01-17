//// Recursive descent parser for commands
////

import gleam/bool
import gleam/int
import gleam/list
import gleam/option
import gleam/result.{try}
import gleam/string
import lore/character/act
import lore/character/character_registry
import lore/character/conn.{type Conn}
import lore/character/events
import lore/character/flag
import lore/character/socials
import lore/character/users
import lore/character/view
import lore/character/view/character_view
import lore/character/view/combat_view
import lore/character/view/communication_view
import lore/character/view/error_view
import lore/character/view/item_view
import lore/world.{type Id, type Item, type Room, Id, StringId}
import lore/world/event
import lore/world/items
import lore/world/room/presence
import lore/world/system_tables
import lore/world/zone/spawner
import splitter.{type Splitter}

type Command(data) {
  Command(verb: Verb, data: data)
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
  Social
  // Admin Commands
  Kick
  Slay
  Smite
  Teleport
  ItemSpawn
  MobileSpawn
  SuperInvisible
  GodMode
}

type Victim {
  Self
  Victim(String)
}

type LookAt {
  LookSelf
  LookItem(world.ItemInstance)
}

type SocialData {
  SocialAuto(social: socials.Social)
  SocialAt(social: socials.Social, at: String)
  SocialNoArg(social: socials.Social)
}

type TeleOtherArgs {
  TeleOther(room_id: Id(Room), victim: Victim)
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
    "l" | "look" -> command(conn, look_at_command, look_args(rest, word))
    "say" -> command(conn, room_comms, say_args(rest, word))
    "whisper" -> command(conn, room_comms, whisper_args(rest, word))
    "emote" -> command(conn, room_comms, emote_text(rest))
    "k" | "kill" -> command(conn, kill_command, keyword_arg(Get, rest, word))
    "op" | "open" ->
      command(conn, door_command, door_args(world.Open, rest, word))
    "cl" | "close" ->
      command(conn, door_command, door_args(world.Closed, rest, word))
    "chat" -> command(conn, chat_command, chat_args(world.General, rest))
    "g" | "get" -> command(conn, get_command, keyword_arg(Get, rest, word))
    "dr" | "drop" -> command(conn, drop_command, keyword_arg(Drop, rest, word))
    "who" -> who_command(conn)
    "quit" -> quit_command(conn)
    "i" | "inventory" -> command_nil(conn, Inventory, inventory_command)
    "" -> conn.prompt(conn)
    // admin commands are prefixed with '@' to not conflict with skills
    "@" -> unknown_command(conn)
    "@kick" ->
      admin_command(conn, role(conn), kick_command, fn() {
        victim_arg(conn, Kick, rest, word)
      })
    "@tele" ->
      admin_command(conn, role(conn), tele_command, fn() {
        tele_arg(rest, word)
      })
    "@tele_to" ->
      admin_command(conn, role(conn), tele_to_command, fn() {
        victim_arg(conn, Teleport, rest, word)
      })
    "@tele_other" ->
      admin_command(conn, role(conn), tele_other_command, fn() {
        tele_other_arg(conn, rest, word)
      })
    "@slay" ->
      admin_command(conn, role(conn), slay_command, fn() {
        victim_arg(conn, Slay, rest, word)
      })
    "@smite" ->
      admin_command(conn, role(conn), smite_command, fn() {
        victim_arg(conn, Smite, rest, word)
      })
    "@spawn_item" ->
      admin_command(conn, role(conn), item_spawn_command, fn() {
        case id(rest, word) {
          Ok(#(item_id, _)) -> Ok(Command(ItemSpawn, item_id))
          Error(_) -> Error(verb_missing_arg_err(ItemSpawn))
        }
      })
    "@spawn_mobile" ->
      admin_command(conn, role(conn), mobile_spawn_command, fn() {
        case id(rest, word) {
          Ok(#(mobile_id, _)) -> Ok(Command(MobileSpawn, mobile_id))
          Error(_) -> Error(verb_missing_arg_err(MobileSpawn))
        }
      })
    "@invis" ->
      admin_command(conn, role(conn), invis_command, fn() {
        Ok(Command(SuperInvisible, Nil))
      })
    "@god_mode" ->
      admin_command(conn, role(conn), god_mode_command, fn() {
        Ok(Command(GodMode, Nil))
      })

    social ->
      command(conn, social_command, social_args(conn, social, rest, word))
  }
}

fn command(
  conn: Conn,
  command_fun: fn(Conn, data) -> Conn,
  args_result: Result(data, String),
) -> Conn {
  case args_result {
    Ok(data) -> command_fun(conn, data)
    Error(error) ->
      conn.renderln(conn, error_view.render_error(error)) |> conn.prompt
  }
}

fn admin_command(
  conn: Conn,
  role: world.Role,
  command_fun: fn(Conn, data) -> Conn,
  args_fun: fn() -> Result(data, String),
) -> Conn {
  use <- bool.lazy_guard(role != world.Admin, fn() { unknown_command(conn) })
  case args_fun() {
    Ok(data) -> command_fun(conn, data)
    Error(error) ->
      conn.renderln(conn, error_view.render_error(error)) |> conn.prompt
  }
}

fn command_nil(
  conn: Conn,
  verb: Verb,
  command_fun: fn(Conn, Command(Nil)) -> Conn,
) -> Conn {
  command_fun(conn, Command(verb, Nil))
}

fn look_args(s: String, word: Splitter) -> Result(Command(String), String) {
  use #(kw, rest) <- result.try(
    keyword(s, word)
    |> result.replace_error("What do you want to look at?"),
  )
  case kw {
    "at" | "in" -> look_args(rest, word)
    _ -> Ok(Command(Look, kw))
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

fn social_args(
  conn: Conn,
  verb: String,
  rest: String,
  word: Splitter,
) -> Result(Command(SocialData), String) {
  let lookups = conn.system_tables(conn)
  use social <- result.try(
    socials.lookup(lookups.socials, verb)
    |> result.replace_error("Huh?"),
  )
  let data = case victim(rest, word) {
    Ok(#(victim, _)) ->
      case is_auto(conn, victim) {
        True -> SocialAuto(social)
        False -> SocialAt(social, victim)
      }
    Error(_) -> SocialNoArg(social)
  }

  Ok(Command(Social, data))
}

fn tele_arg(s: String, word: Splitter) -> Result(Command(Id(Room)), String) {
  case id(s, word) {
    Ok(#(room_id, _)) -> Ok(Command(Teleport, room_id))
    Error(_) -> Error(verb_missing_arg_err(Teleport))
  }
}

fn tele_other_arg(
  conn: Conn,
  s: String,
  word: Splitter,
) -> Result(Command(TeleOtherArgs), String) {
  use #(victim, rest) <- result.try(
    victim(s, word)
    |> result.replace_error(verb_missing_arg_err(Teleport)),
  )
  let victim = case is_auto(conn, victim) {
    True -> Self
    False -> Victim(victim)
  }
  use #(room_id, _) <- try(
    id(rest, word)
    |> result.replace_error("Where do you want to teleport this person to?"),
  )
  TeleOther(room_id:, victim:)
  |> Command(Teleport, _)
  |> Ok
}

fn victim_arg(
  conn: Conn,
  verb: Verb,
  s: String,
  word: Splitter,
) -> Result(Command(Victim), String) {
  use #(victim, _) <- result.try(
    victim(s, word)
    |> result.replace_error(verb_missing_arg_err(verb)),
  )
  case is_auto(conn, victim) {
    True -> Command(verb, Self)
    False -> Command(verb, Victim(victim))
  }
  |> Ok
}

fn quote(s: String) -> String {
  let #(text, _) = splitter.new(["\r\n", "\n"]) |> splitter.split_before(s)
  string.capitalise(text)
}

fn keyword_arg(
  verb: Verb,
  s: String,
  word: Splitter,
) -> Result(Command(String), String) {
  case keyword(s, word) {
    Ok(#(keyword, _)) -> Ok(Command(verb, keyword))
    Error(_) -> Error(verb_missing_arg_err(verb))
  }
}

fn keyword(s: String, word: Splitter) -> Result(#(String, String), Nil) {
  let #(slice, _, rest) = splitter.split(word, s)
  case slice {
    // an empty string is unexpected
    "" -> Error(Nil)
    // ignore articles
    "a" | "an" | "the" -> keyword(rest, word)
    keyword -> Ok(#(string.lowercase(keyword), string.trim_start(rest)))
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
  try_again: List(#(String, fn(String) -> Result(#(String, String), Nil))),
  acc: List(#(String, String)),
) -> #(List(#(String, String)), String) {
  // Any failed parsers will be stashed in try_again in case the failure
  // is due to option order
  case parsers {
    [] -> #(acc, s)
    [#(tag, parser_fun) as parser, ..rest] ->
      case parser_fun(s) {
        Ok(#(option, s)) if try_again == [] ->
          options_loop(s, rest, [], [#(tag, option), ..acc])

        Ok(#(option, s)) ->
          list.append(rest, try_again)
          |> options_loop(s, _, [], [#(tag, option), ..acc])

        // since options could be in any order, try again later if there is
        // ever a success
        Error(Nil) -> options_loop(s, rest, [parser, ..try_again], acc)
      }
  }
}

fn victim(s: String, word: Splitter) -> Result(#(String, String), Nil) {
  use #(slice, rest) <- result.try(keyword(s, word))
  case slice {
    "@" <> slice -> Ok(#(slice, rest))
    "at" -> keyword(rest, word)
    _ -> Ok(#(slice, rest))
  }
}

fn at(s: String, word: Splitter) -> Result(#(String, String), Nil) {
  let #(slice, _, rest) = splitter.split(word, s)
  let rest = string.trim_start(rest)
  case string.lowercase(slice) {
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

fn id(s: String, word: Splitter) -> Result(#(Id(a), String), Nil) {
  let #(slice, _, rest) = splitter.split(word, s)
  use parsed <- result.try(int.parse(slice))
  Ok(#(Id(parsed), rest))
}

//
// Command Functions
//

fn move_command(conn: Conn, direction: world.Direction) -> Conn {
  let character = conn.character_get(conn)
  case character.fighting {
    world.NoTarget -> conn.action(conn, act.move(direction))
    world.Fighting(..) ->
      conn
      |> conn.renderln(error_view.already_fighting())
      |> conn.prompt()
  }
}

fn look_command(conn: Conn, _: Command(Nil)) -> Conn {
  conn.event(conn, event.Look)
}

fn look_at_command(conn: Conn, command: Command(String)) -> Conn {
  let search_term = command.data
  let self = conn.character_get(conn)
  let found_result = {
    use <- bool.guard(
      search_term == "self"
        || list.any(self.keywords, fn(keyword) { search_term == keyword }),
      Ok(LookSelf),
    )
    list.find(self.inventory, fn(item_instance) {
      list.any(item_instance.keywords, fn(keyword) { search_term == keyword })
    })
    |> result.map(LookItem)
  }

  case found_result {
    Ok(LookSelf) ->
      conn
      |> conn.renderln(character_view.look_at(self))
      |> conn.prompt()

    Ok(LookItem(item_instance)) -> events.item_look_at(conn, item_instance)

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
  let world.MobileInternal(inventory:, ..) = conn.character_get(conn)
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
  let self = conn.character_get(conn)
  case !is_auto(conn, command.data) {
    True if self.fighting == world.NoTarget ->
      event.CombatRequestData(
        victim: event.Keyword(command.data),
        dam_roll: world.random(8),
        is_round_based: False,
      )
      |> act.kill
      |> conn.action(conn, _)

    True ->
      conn
      |> conn.renderln(error_view.already_fighting())
      |> conn.prompt()

    False ->
      conn
      |> conn.renderln(error_view.cannot_target_self())
      |> conn.prompt()
  }
}

fn is_auto(conn: Conn, search_term: String) -> Bool {
  let self = conn.character_get(conn)
  case search_term {
    "self" -> True
    search_term ->
      self.id == StringId(string.uppercase(search_term))
      || list.any(self.keywords, fn(keyword) { search_term == keyword })
  }
}

fn inventory_command(conn: Conn, _command: Command(Nil)) -> Conn {
  let system_tables.Lookup(items:, ..) = conn.system_tables(conn)
  let character = conn.character_get(conn)

  conn.renderln(conn, item_view.inventory(items, character))
  |> conn.prompt()
}

fn who_command(conn: Conn) -> Conn {
  let system_tables.Lookup(user:, ..) = conn.system_tables(conn)
  conn.render(conn, character_view.who_list(users.players_logged_in(user)))
}

fn quit_command(conn: Conn) -> Conn {
  conn
  |> conn.renderln(character_view.quit())
  |> conn.terminate
}

fn social_command(conn: Conn, command: Command(SocialData)) -> Conn {
  let comm_data = case command.data {
    SocialAuto(social:) ->
      view.ReportBasic(self: social.char_auto, witness: social.others_auto)
      |> event.SocialData()

    SocialNoArg(social:) ->
      view.ReportBasic(self: social.char_no_arg, witness: social.others_no_arg)
      |> event.SocialData()

    SocialAt(social:, at:) ->
      view.ReportAdvanced(
        self: social.char_found,
        witness: social.others_found,
        victim: social.victim_found,
      )
      |> event.SocialAtData(at:)
  }

  conn.action(conn, act.communicate(comm_data))
}

fn kick_command(conn: Conn, command: Command(Victim)) -> Conn {
  let system_tables.Lookup(user:, character:, ..) = conn.system_tables(conn)
  case command.data {
    Self ->
      conn
      |> conn.renderln("You cannot do that to yourself!" |> view.Leaf)
      |> conn.prompt

    Victim(victim) -> {
      let result = {
        use user <- try(users.lookup(user, victim))
        use user_subject <- try(character_registry.whereis(character, user.id))
        let world.MobileInternal(name:, ..) = conn.character_get(conn)
        let user_name = string.capitalise(victim)
        conn
        |> conn.character_event(event.Kick(initiated_by: name), user_subject)
        |> conn.renderln(["Kicking ", user_name, "..."] |> view.Leaves)
        |> conn.prompt
        |> Ok
      }

      case result {
        Ok(conn) -> conn

        Error(_) ->
          conn
          |> conn.renderln(error_view.user_not_found(victim))
          |> conn.prompt
      }
    }
  }
}

fn tele_command(conn: Conn, command: Command(Id(Room))) -> Conn {
  let room_id = command.data
  conn.event(conn, event.TeleportRequest(room_id))
}

fn tele_to_command(conn: Conn, command: Command(Victim)) -> Conn {
  let system_tables.Lookup(user:, presence:, ..) = conn.system_tables(conn)
  case command.data {
    Self ->
      conn |> conn.renderln(view.Leaf("You're already there!")) |> conn.prompt

    Victim(victim) -> {
      let result = {
        use users.User(id:, ..) <- try(users.lookup(user, victim))
        use room_id <- try(presence.lookup(presence, id))
        conn.event(conn, event.TeleportRequest(room_id))
        |> Ok
      }

      let result = {
        use _ <- result.try_recover(result)
        let victim_id = StringId(string.uppercase(victim))
        use room_id <- try(presence.lookup(presence, victim_id))
        conn.event(conn, event.TeleportRequest(room_id))
        |> Ok
      }

      case result {
        Ok(update) -> update
        Error(_) -> conn.renderln(conn, view.Leaf("Cannot find that user."))
      }
    }
  }
}

fn tele_other_command(conn: Conn, command: Command(TeleOtherArgs)) -> Conn {
  let TeleOther(room_id:, victim:) = command.data
  let system_tables.Lookup(user:, character:, ..) = conn.system_tables(conn)
  case victim {
    Self -> tele_command(conn, Command(Teleport, room_id))
    Victim(victim) -> {
      let result = {
        use users.User(id:, ..) <- try(users.lookup(user, victim))
        character_registry.whereis(character, id)
      }

      case result {
        Ok(subject) ->
          conn.character_event(conn, event.Teleport(room_id:), subject)
        Error(_) -> conn
      }
    }
  }
}

fn slay_command(conn: Conn, command: Command(Victim)) -> Conn {
  case command.data {
    Victim(victim) -> conn.event(conn, event.Slay(event.Keyword(victim)))
    Self ->
      conn
      |> conn.renderln(view.Leaf("That would be unwise."))
      |> conn.prompt
  }
}

fn smite_command(conn: Conn, command: Command(Victim)) -> Conn {
  case command.data {
    Victim(victim) -> {
      let result = {
        let system_tables.Lookup(presence:, ..) = conn.system_tables(conn)
        let victim_id = StringId(string.uppercase(victim))
        use room_id <- try(presence.lookup(presence, victim_id))
        conn.event_to_room(conn, room_id, event.Slay(event.SearchId(victim_id)))
        |> conn.renderln(combat_view.smite_1p(victim))
        |> conn.prompt
        |> Ok
      }

      case result {
        Ok(conn) -> conn
        Error(_) ->
          conn
          |> conn.renderln(["Unable to find id '", victim, "'"] |> view.Leaves)
          |> conn.prompt
      }
    }

    Self ->
      conn |> conn.renderln(view.Leaf("That would be unwise.")) |> conn.prompt
  }
}

fn item_spawn_command(conn: Conn, command: Command(Id(Item))) -> Conn {
  let result = {
    let item_id = command.data
    let system_tables.Lookup(items:, ..) = conn.system_tables(conn)
    use item_instance <- try(items.instance(items, item_id))
    use loaded <- try(items.load(items, item_id))
    let character = conn.character_get(conn)
    let inventory = [item_instance, ..character.inventory]
    world.MobileInternal(..character, inventory:)
    |> conn.character_put(conn, _)
    |> conn.renderln(item_view.spawn_item(loaded))
    |> conn.prompt
    |> Ok
  }

  case result {
    Ok(update) -> update

    Error(_) ->
      conn |> conn.renderln("Invalid item id." |> view.Leaf) |> conn.prompt
  }
}

fn mobile_spawn_command(conn: Conn, command: Command(Id(world.Npc))) -> Conn {
  let lookup = conn.system_tables(conn)
  let mobile_id = command.data
  let self = conn.character_get(conn)
  case spawner.spawn_mobile_ad_hoc(lookup, mobile_id, self.room_id) {
    Ok(_) -> conn
    Error(_) ->
      conn |> conn.renderln("Spawn failed." |> view.Leaf) |> conn.prompt()
  }
}

fn invis_command(conn: Conn, _: Command(_)) -> Conn {
  let self = conn.character_get(conn)
  let affects = self.affects
  let flags = flag.affect_toggle(affects.flags, flag.SuperInvisible)
  let msg = case flag.affect_has(flags, flag.SuperInvisible) {
    True -> "You cloak yourself in night. You are now invisible!"
    False ->
      "You remove your nighted cloak and walk in the light. You are visible!"
  }

  world.MobileInternal(..self, affects: world.Affects(flags:))
  |> conn.character_put(conn, _)
  |> conn.renderln(view.Leaf(msg))
  |> conn.prompt
  |> conn.event(event.UpdateCharacter)
}

fn god_mode_command(conn: Conn, _: Command(_)) -> Conn {
  let self = conn.character_get(conn)
  let affects = self.affects
  let flags = flag.affect_toggle(affects.flags, flag.GodMode)
  let msg = case flag.affect_has(flags, flag.GodMode) {
    True ->
      "Your flesh no longer knows pain or death. You have activated god mode!"
    False ->
      "You make yourself vulnerable to the biting sting of mortality. You have deactivated god mode!"
  }

  world.MobileInternal(..self, affects: world.Affects(flags:))
  |> conn.character_put(conn, _)
  |> conn.renderln(view.Leaf(msg))
  |> conn.prompt
  |> conn.event(event.UpdateCharacter)
}

fn unknown_command(conn: Conn) -> Conn {
  conn
  |> conn.renderln(view.Leaf("Huh?"))
  |> conn.prompt
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

fn role(conn: Conn) -> world.Role {
  conn.character_get(conn).role
}

fn verb_missing_arg_err(verb: Verb) -> String {
  case verb {
    Say -> "What do you want to say?"
    Whisper -> "Who do you want to whisper to?"
    Emote -> "What do you want to emote?"
    Open -> "What do you want to open?"
    Close -> "What do you want to close?"
    Chat -> "What do you want to chat?"
    Get -> "What do you want to get?"
    Drop -> "What do you want to drop?"
    Kill -> "Who do you want to kill?"
    Kick -> "Who do you want to kick?"
    Teleport -> "Where do you want to teleport?"
    Slay -> "Who do you want to slay?"
    Smite -> "Who do you want to smite from afar?"
    Look -> "What do you want to look at?"
    ItemSpawn -> "What item do you want to spawn?"
    MobileSpawn -> "What mobile do you want to spawn?"
    // verbs without args
    Inventory -> ""
    Social -> ""
    SuperInvisible -> ""
    GodMode -> ""
  }
}
