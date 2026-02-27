//// Text renders to be displayed to connections.
////

import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result.{try}
import gleam/string_tree
import lore/character/flag
import lore/character/users
import lore/character/view.{type View}
import lore/world.{type Direction, type Mobile, type Room, type StringId}
import lore/world/event
import lore/world/items
import lore/world/mapper
import lore/world/named_actors

const color_room_title = "&189"

const color_bwhite = "&W"

const color_reset = "0;"

pub fn prompt(character: world.MobileInternal) -> View {
  let world.MobileInternal(hp:, hp_max:, ..) = character
  let hp = int.to_string(hp)
  let hp_max = int.to_string(hp_max)

  ["<&R", hp, "/", hp_max, "hp0;> "]
  |> view.Leaves
}

//
// Move views
//

pub fn notify_arrive(character: Mobile, room_exit: Option(Direction)) -> View {
  let exit = case room_exit {
    Some(direction) -> direction
    None -> world.CustomExit("some unseen corner.")
  }

  case exit {
    world.CustomExit(custom_message) -> [
      character.name,
      " arrives from ",
      custom_message,
    ]
    _ -> [character.name, " arrives from the ", world.direction_to_string(exit)]
  }
  |> view.Leaves
}

pub fn notify_depart(character: Mobile, room_exit: Option(Direction)) -> View {
  case room_exit {
    Some(keyword) -> [
      character.name,
      " departs ",
      world.direction_to_string(keyword),
      ".",
    ]
    None -> [character.name, " seems to have gone missing!"]
  }
  |> view.Leaves
}

pub fn notify_spawn(character: Mobile) -> View {
  [character.name, " appears in a poof of smoke!"]
  |> view.Leaves
}

pub fn exit(room_exit: Option(Direction)) -> View {
  case room_exit {
    Some(keyword) ->
      ["You depart ", world.direction_to_string(keyword), "."]
      |> view.Leaves

    None -> "You slip through a crack in interstitial space!" |> view.Leaf
  }
}

//
// Look view
//

pub fn room_with_mini_map_impure(
  room: Room,
  observer: world.Mobile,
  lookup: named_actors.Lookup,
) -> View {
  let loaded = items.load_instances(lookup.items, room.items)
  let room = world.Room(..room, items: loaded)
  let mini_map =
    mapper.render_mini_map(lookup.mapper, room.id)
    |> string_tree.join("\n")
    |> string_tree.append("\n")
    |> view.Tree

  [
    view.blank(),
    mini_map,
    room_view(room, observer),
  ]
  |> view.join("\n")
}

pub fn room_view(room: Room, observer: world.Mobile) -> View {
  let preamble =
    [color_room_title, room.name, color_reset, "\n  ", room.description, "\n"]
    |> string_tree.from_strings

  let exits =
    room.exits
    |> list.map(fn(exit) {
      case exit.door {
        Some(world.Door(state: world.Closed, ..)) ->
          ["+", world.direction_to_string(exit.keyword)]
          |> string_tree.from_strings

        Some(world.Door(state: world.Open, ..)) ->
          ["'", world.direction_to_string(exit.keyword)]
          |> string_tree.from_strings

        None ->
          world.direction_to_string(exit.keyword)
          |> string_tree.from_string
      }
    })
    |> string_tree.join(" ")
    |> string_tree.prepend("&189[Obvious Exits: &W")
    |> string_tree.append("&189]0;\n")

  let observer_id = observer.id
  let mobiles =
    room.characters
    // filter out observer
    |> list.filter(fn(character) {
      observer_id != character.id
      && !flag.affect_has(character.affects, flag.SuperInvisible)
    })
    |> list.map(fn(character) {
      [character.short, "\n"]
      |> string_tree.from_strings
    })
    |> string_tree.concat

  let items =
    list.filter_map(room.items, fn(item_instance) {
      case item_instance.item {
        world.Loaded(world.Item(short:, ..)) ->
          ["    ", short, "\n"]
          |> string_tree.from_strings
          |> Ok

        world.Loading(_) -> Error(Nil)
      }
    })
    |> string_tree.concat

  [preamble, exits, items, mobiles]
  |> list.filter(fn(tree) { !string_tree.is_empty(tree) })
  |> string_tree.concat
  |> view.Tree
}

//
// Login View
//

pub fn login_greeting() -> View {
  "Welcome to the server!"
  |> view.Leaf
}

pub fn login_name() -> View {
  "Enter a name: "
  |> view.Leaf
}

pub fn password(name: String) -> View {
  ["Enter password for ", name, ": "]
  |> view.Leaves
}

pub fn new_name_confirm(name: String) -> View {
  [
    "There is no account associated with ",
    name,
    ".\n",
    "Would you like to create one? (y/n): ",
  ]
  |> view.Leaves
}

pub fn name_abort() -> View {
  "OK, what name would you like to login as? "
  |> view.Leaf
}

pub fn new_password1() -> View {
  "Enter a password for this account: "
  |> view.Leaf
}

pub fn new_password2() -> View {
  "Enter the password a second time: "
  |> view.Leaf
}

pub fn password_mismatch_err() -> View {
  "Passwords do not match. Please enter again: "
  |> view.Leaf
}

pub fn password_invalid() -> View {
  "Password is invalid. Try again: "
  |> view.Leaf
}

pub fn password_err() -> View {
  "Incorrect password. Try again: "
  |> view.Leaf
}

pub fn greeting(name: String) -> View {
  ["Hello, ", name, "!"]
  |> view.Leaves
}

//
// Items
//
pub fn inventory(
  item_table: process.Name(items.Message),
  self: world.MobileInternal,
) -> View {
  case container_contents(item_table, self.inventory) {
    items if items != [] ->
      [view.Leaf("You are carrying:"), ..items]
      |> view.join("\n")

    _ -> view.Leaf("You are carrying:\n    Nothing.")
  }
}

pub fn equipment(
  item_table: process.Name(items.Message),
  self: world.MobileInternal,
) -> View {
  let equipment = self.equipment
  let is_naked =
    dict.is_empty(equipment)
    || list.all(dict.values(equipment), fn(wearing) {
      wearing == world.EmptySlot
    })

  let equipment =
    equipment
    |> dict.to_list
    |> list.filter_map(fn(key_val) {
      let #(wear_slot, wearing) = key_val
      let wear_slot = wear_slot_to_string(wear_slot)
      case wearing {
        world.Wearing(item_instance) ->
          items.load_from_instance(item_table, item_instance)
          |> result.map(fn(item) { view.Leaves([wear_slot, ": ", item.name]) })

        world.EmptySlot ->
          [
            wear_slot,
            ": Empty",
          ]
          |> view.Leaves
          |> Ok
      }
    })

  let prelude = case is_naked {
    True -> ["You are NAKED!"] |> view.Leaves
    False -> ["You are wearing:"] |> view.Leaves
  }

  view.join([prelude, ..equipment], "\n")
}

pub fn item_contains(
  item_table: process.Name(items.Message),
  instances: List(world.ItemInstance),
) -> View {
  case container_contents(item_table, instances) {
    items if items != [] ->
      [view.Leaf("You look inside and see:"), ..items]
      |> view.join("\n")

    _ -> view.Leaf("You look inside and see:\n    Nothing.")
  }
}

pub fn container_contents(
  item_table: process.Name(items.Message),
  instances: List(world.ItemInstance),
) -> List(View) {
  list.filter_map(instances, items.load_from_instance(item_table, _))
  |> list.map(fn(item) { view.Leaves(["  ", item.name]) })
}

pub fn item_get(
  self: world.MobileInternal,
  acting_character: world.Mobile,
  item: world.Item,
) -> View {
  case view.perspective_simple(self, acting_character) {
    view.Self -> ["You get ", item.name, "."]
    view.Witness -> [
      character_name(acting_character),
      " gets ",
      item.name,
    ]
  }
  |> view.Leaves
}

pub fn item_drop(
  self: world.MobileInternal,
  acting_character: world.Mobile,
  item: world.Item,
) -> View {
  case view.perspective_simple(self, acting_character) {
    view.Self -> ["You drop ", item.name, "."]
    view.Witness -> [
      character_name(acting_character),
      " drops ",
      item.name,
    ]
  }
  |> view.Leaves
}

pub fn item_inspect(item: world.Item) -> View {
  [item.name, "\n  ", item.long] |> view.Leaves
}

pub fn spawn_item(item: world.Item) -> View {
  [
    "You weave stray threads of light together, manifesting ",
    item.name,
    " from the ether.",
  ]
  |> view.Leaves
}

pub fn item_wear(item: world.Item) -> View {
  view.Leaves(["You wear ", item.name, "."])
}

pub fn item_remove(
  items_table: process.Name(items.Message),
  item: world.ItemInstance,
) -> View {
  case items.load_from_instance(items_table, item) {
    Ok(item) -> view.Leaves(["You take off ", item.name, "."])
    Error(_) -> view.Leaf("Unable to load item name.")
  }
}

pub fn wear_slot_to_string(wear_slot: world.WearSlot) -> String {
  case wear_slot {
    world.Arms -> "arms"
    world.CannotWear -> "[Invalid Wear Slot]"
  }
}

//
// Character Views
//
//
pub fn quit() -> View {
  view.Leaf("See you next time!~")
}

pub fn character_name(character: world.Mobile) -> String {
  character.name
}

pub fn who_list(users: List(users.User)) -> View {
  let num_users = list.length(users)
  let preamble =
    [
      "There are currently ",
      color_bwhite,
      int.to_string(num_users),
      color_reset,
      " users online:\n",
    ]
    |> string_tree.from_strings

  list.fold(users, preamble, fn(acc, user) {
    ["    ", user.name, "\n"]
    |> string_tree.from_strings
    |> string_tree.append_tree(acc, _)
  })
  |> view.Tree
}

pub fn look_at(character: world.MobileInternal) -> View {
  character.name
  |> view.Leaf
}

//
// Error views
//

pub fn error_parse() -> View {
  "huh?"
  |> view.Leaf
}

pub fn error(error: String) -> View {
  view.Leaf(error)
}

pub fn error_room_request(error: world.ErrorRoomRequest) -> View {
  case error {
    world.UnknownExit(direction:) ->
      ["There is no exit ", direction_to_string(direction), "."]
      |> view.Leaves

    world.CharacterLookupFailed ->
      "That character doesn't seem to be here."
      |> view.Leaf

    world.ItemLookupFailed(keyword:) ->
      ["Unable to find item: ", keyword]
      |> view.Leaves

    world.RoomLookupFailed(..) ->
      "So strange. It's as if that destination doesn't want to be found."
      |> view.Leaf

    world.MoveErr(move_err) -> error_move(move_err)

    world.DoorErr(door_err) -> error_door(door_err)

    world.NotFound(keyword) ->
      ["Unable to find '", keyword, "'."] |> view.Leaves

    world.PvpForbidden -> "You cannot attack other players." |> view.Leaf

    world.VictimHasGodMode ->
      "You are forbidden to attack an immortal" |> view.Leaf
  }
}

pub fn error_item(err: world.ErrorItem) -> View {
  case err {
    world.UnknownItem(search_term:, verb:) -> [
      "You are not ",
      verb,
      " anything that matches ",
      search_term,
      ".",
    ]
    world.CannotBeWorn(item:) -> [item.name, " cannot be worn."]
    world.CannotWield(item:) -> ["You cannot be wield ", item.name]
    world.WearSlotFull(wear_slot:, item:) -> [
      "You must remove ",
      item.name,
      " from your ",
      wear_slot_to_string(wear_slot),
      " to wear that.",
    ]
    world.WearSlotMissing(wear_slot:) -> [
      "You lack the ",
      wear_slot_to_string(wear_slot),
      " to wear that.",
    ]
    world.InvalidItemId(item_id: world.Id(item_id)) -> [
      "Item id ",
      int.to_string(item_id),
      " is invalid.",
    ]
  }
  |> view.Leaves
}

pub fn error_not_carrying() -> View {
  "You aren't carrying that." |> view.Leaf
}

fn error_move(error: world.ErrorMove) -> View {
  case error {
    world.Unauthorized -> "You lack the permissions to enter." |> view.Leaf
  }
}

fn error_door(error: world.ErrorDoor) -> View {
  case error {
    world.DoorLocked -> "The door is closed and locked." |> view.Leaf
    world.NoChangeNeeded(state) ->
      ["The door is already ", access_to_string(state), "."] |> view.Leaves
    world.MissingDoor(direction) ->
      ["There is no door ", direction_to_string(direction), "."] |> view.Leaves
    world.DoorClosed -> "The door is closed." |> view.Leaf
  }
}

pub fn error_cannot_target_self() {
  "That would be unwise." |> view.Leaf
}

pub fn error_already_fighting() {
  "You are fighting for your life!" |> view.Leaf
}

pub fn error_user_not_found(name: String) -> View {
  ["User ", name, " not found."]
  |> view.Leaves
}

fn direction_to_string(direction: world.Direction) -> String {
  case direction {
    world.North -> "north"
    world.South -> "south"
    world.East -> "east"
    world.West -> "west"
    world.Up -> "up"
    world.Down -> "down"
    world.CustomExit(custom) -> custom
  }
}

fn access_to_string(access: world.AccessState) -> String {
  case access {
    world.Open -> "open"
    world.Closed -> "closed"
  }
}

//
// Door Views
//

pub fn door_notify(
  self: world.MobileInternal,
  acting_character: world.Mobile,
  data: event.DoorNotifyData,
) -> View {
  let direction = world.direction_to_string(data.exit.keyword)

  case view.perspective_simple(self, acting_character) {
    view.Self -> [
      "You ",
      door_verb(view.Self, data.update),
      " the ",
      direction,
      " door.",
    ]

    view.Witness if data.is_subject_observable -> [
      acting_character.name,
      " ",
      door_verb(view.Witness, data.update),
      " the door ",
      direction,
      ".",
    ]

    view.Witness -> [
      "The ",
      direction,
      " door ",
      door_verb(view.Self, data.update),
      ".",
    ]
  }
  |> view.Leaves
}

fn door_verb(
  perspective: view.PerspectiveSimple,
  access: world.AccessState,
) -> String {
  case perspective, access {
    view.Self, world.Open -> "open"
    view.Witness, world.Open -> "opens"
    view.Self, world.Closed -> "close"
    view.Witness, world.Closed -> "closes"
  }
}

//
// Communication View
//
type Self {
  Self
  NotSelf
}

type CommunicationVerb {
  Say
  Ask
  Exclaim
}

pub fn communication(
  self: world.MobileInternal,
  acting_character: world.Mobile,
  data: event.CommunicationData,
) -> View {
  let self_id = self.id
  let is_acting_character = self_id == acting_character.id

  case data {
    event.Say(text:, adverb:) if is_acting_character ->
      [
        "You ",
        adverb_to_string(adverb),
        verb(text, Self),
        ", \"",
        text,
        "\"",
      ]
      |> view.Leaves

    event.Say(text:, adverb:) ->
      [
        character_name(acting_character),
        " ",
        adverb_to_string(adverb),
        verb(text, NotSelf),
        ", \"",
        text,
        "\"",
      ]
      |> view.Leaves

    event.SayAt(text:, at:, adverb:) if is_acting_character && self_id == at.id ->
      [
        "You ",
        adverb_to_string(adverb),
        "mutter to yourself, \"",
        text,
        "\"",
      ]
      |> view.Leaves

    event.SayAt(text:, at:, adverb:) if is_acting_character ->
      [
        "You ",
        adverb_to_string(adverb),
        verb_to(text, Self),
        " ",
        character_name(at),
        ", \"",
        text,
        "\"",
      ]
      |> view.Leaves

    event.SayAt(text:, at:, adverb:) if acting_character.id == at.id ->
      [
        character_name(acting_character),
        adverb_to_string(adverb),
        " mutters to ",
        pronoun_self(acting_character),
        ", \"",
        text,
        "\"",
      ]
      |> view.Leaves

    event.SayAt(text:, at:, adverb:) if self_id == at.id ->
      [
        character_name(acting_character),
        " ",
        adverb_to_string(adverb),
        verb_to(text, NotSelf),
        " you, \"",
        text,
        "\"",
      ]
      |> view.Leaves

    event.SayAt(text:, at:, adverb:) -> {
      let acting_character = character_name(acting_character)
      let victim = character_name(at)
      [
        acting_character,
        " ",
        adverb_to_string(adverb),
        verb_to(text, NotSelf),
        " ",
        victim,
        ", \"",
        text,
        "\"",
      ]
      |> view.Leaves
    }

    event.Whisper(text:, at:) if is_acting_character && self_id == at.id ->
      [
        "You whisper to yourself, \"",
        text,
        "\"",
      ]
      |> view.Leaves

    event.Whisper(text:, at:) if is_acting_character ->
      [
        "You whisper to ",
        character_name(at),
        ", \"",
        text,
        "\"",
      ]
      |> view.Leaves

    event.Whisper(text:, at:) if self_id == at.id ->
      [
        character_name(acting_character),
        " whispers in your ear, \"",
        text,
        "\"",
      ]
      |> view.Leaves

    event.Whisper(at:, ..) -> {
      let acting_character = character_name(acting_character)
      let victim = character_name(at)
      [acting_character, " whispers something to ", victim, "."]
      |> view.Leaves
    }

    event.Emote(text:) ->
      [character_name(acting_character), " ", text] |> view.Leaves

    event.Social(report:) ->
      view.render_report(report, self, acting_character, None)

    event.SocialAt(report:, at:) ->
      view.render_report(report, self, acting_character, Some(at))
  }
}

pub fn chat(data: event.ChatData) -> View {
  let event.ChatData(channel:, username:, text:) = data
  [
    "(",
    channel_to_string(channel),
    ") ",
    username,
    ": \"",
    text,
    "\"",
  ]
  |> view.Leaves
}

pub fn empty(verb: String) -> View {
  ["What do you want to ", verb, "?"]
  |> view.Leaves
}

pub fn channel_not_subscribed(channel: world.ChatChannel) -> View {
  [
    "You are not subscribed to channel ",
    channel_to_string(channel),
    ".",
  ]
  |> view.Leaves
}

pub fn already_subscribed(channel: world.ChatChannel) -> View {
  [
    "You are already subscribed to channel ",
    channel_to_string(channel),
    ".",
  ]
  |> view.Leaves
}

pub fn subscribe_success(channel: world.ChatChannel) -> View {
  [
    "You subscribed to channel ",
    channel_to_string(channel),
    ".",
  ]
  |> view.Leaves
}

pub fn subscribe_fail(channel: world.ChatChannel) -> View {
  [
    "You failed to subscribe to channel ",
    channel_to_string(channel),
    ".",
  ]
  |> view.Leaves
}

pub fn unsubscribe_success(channel: world.ChatChannel) -> View {
  [
    "You unsubscribed from channel ",
    channel_to_string(channel),
    ".",
  ]
  |> view.Leaves
}

pub fn unsubscribe_fail(channel: world.ChatChannel) -> View {
  [
    "You failed to unsubscribe from channel ",
    channel_to_string(channel),
    ".",
  ]
  |> view.Leaves
}

pub fn already_unsubscribed(channel: world.ChatChannel) -> View {
  [
    "You are not subscribed to channel ",
    channel_to_string(channel),
    ".",
  ]
  |> view.Leaves
}

fn channel_to_string(channel: world.ChatChannel) -> String {
  case channel {
    world.General -> "General"
  }
}

fn verb(text: String, witness: Self) -> String {
  case to_communication_verb(text), witness {
    Ask, Self -> "ask"
    Ask, NotSelf -> "asks"
    Exclaim, Self -> "exclaim"
    Exclaim, NotSelf -> "exclaims"
    Say, Self -> "say"
    Say, NotSelf -> "says"
  }
}

fn verb_to(text: String, witness: Self) -> String {
  case to_communication_verb(text), witness {
    Ask, Self -> "ask"
    Ask, NotSelf -> "asks"
    Exclaim, Self -> "yell at"
    Exclaim, NotSelf -> "yells at"
    Say, Self -> "say to"
    Say, NotSelf -> "says to"
  }
}

fn to_communication_verb(text: String) -> CommunicationVerb {
  case last_character(bit_array.from_string(text), <<>>) {
    <<"?">> -> Ask
    <<"!">> -> Exclaim
    _ -> Say
  }
}

fn last_character(binary: BitArray, last_char: BitArray) -> BitArray {
  case binary {
    <<>> -> last_char
    <<a:size(8), rest:bits>> -> last_character(rest, <<a>>)
    _ -> <<>>
  }
}

fn pronoun_self(acting_character: world.Mobile) -> String {
  let world.Pronoun(himself:, ..) = world.pronouns(acting_character.pronouns)
  himself
}

fn adverb_to_string(adverb: Option(String)) -> String {
  case adverb {
    Some(adverb) -> adverb <> " "
    None -> ""
  }
}

//
// Combat Views
//
type Perspective {
  Attacker
  Victim
  Witness
}

pub fn combat_notify(
  self: world.MobileInternal,
  commit: event.CombatCommitData,
) -> View {
  let event.CombatCommitData(attacker:, victim:, ..) = commit

  let perspective = perspective(self, attacker, victim)
  let view = damage_notify(perspective, commit)

  case victim.hp <= 0 {
    True -> view.join([view, death_notify(perspective, commit)], "\n")
    False -> view
  }
}

pub fn round_report(
  self: world.MobileInternal,
  participants: Dict(StringId(Mobile), Mobile),
  commits: List(event.CombatPollData),
) -> View {
  list.filter_map(commits, fn(commit) {
    let event.CombatPollData(attacker_id:, victim_id:, dam_roll: damage) =
      commit
    use attacker <- try(dict.get(participants, attacker_id))
    use victim <- try(dict.get(participants, victim_id))
    let commit = event.CombatCommitData(attacker:, victim:, damage:)
    let perspective = perspective(self, attacker, victim)
    let view = damage_notify(perspective, commit)
    case victim.hp <= 0 {
      True -> view.join([view, death_notify(perspective, commit)], "\n")
      False -> view
    }
    |> Ok
  })
  |> view.join("\n")
}

pub fn round_summary(
  self: world.MobileInternal,
  participants: Dict(StringId(Mobile), Mobile),
) -> View {
  let participants = dict.delete(participants, self.id) |> dict.values

  let prelude =
    [
      "You ",
      health_feedback_1p(self),
    ]
    |> view.Leaves

  let rest =
    list.filter_map(participants, fn(participant) {
      case participant.hp > 0 {
        True ->
          [
            character_name(participant),
            " ",
            health_feedback_3p(participant),
          ]
          |> view.Leaves
          |> Ok

        False -> Error(Nil)
      }
    })

  view.join([prelude, ..rest], "\n")
}

pub fn smite_1p(name: String) -> View {
  ["You hurl a thunderbolt in ", name, "'s direction."]
  |> view.Leaves
}

fn damage_notify(perspective: Perspective, data: event.CombatCommitData) -> View {
  let event.CombatCommitData(victim:, attacker:, damage:) = data
  let victim_hp_max = victim.hp_max

  case perspective {
    Attacker -> [
      "Your strike ",
      damage_feedback(damage, victim_hp_max),
      " ",
      character_name(victim),
      "! (",
      int.to_string(damage),
      ")",
    ]

    Victim -> [
      character_name(attacker),
      "'s strike ",
      damage_feedback(damage, victim_hp_max),
      " you!",
    ]

    Witness -> [
      character_name(attacker),
      " strikes ",
      character_name(victim),
      "!",
    ]
  }
  |> view.Leaves
}

fn death_notify(perspective: Perspective, data: event.CombatCommitData) -> View {
  let event.CombatCommitData(victim:, attacker:, ..) = data
  case perspective {
    Attacker -> ["&YYou have killed ", character_name(victim), "!0;"]

    Victim -> [
      "&Y",
      character_name(attacker),
      " has killed you!0;",
    ]

    Witness -> [
      "&Y",
      character_name(attacker),
      " has killed ",
      character_name(victim),
      "!0;",
    ]
  }
  |> view.Leaves
}

fn perspective(
  self: world.MobileInternal,
  attacker: world.Mobile,
  victim: world.Mobile,
) -> Perspective {
  case self.id {
    self if self == attacker.id -> Attacker
    self if self == victim.id -> Victim
    _ -> Witness
  }
}

fn damage_feedback(damage: Int, victim_hp_max: Int) -> String {
  let dam_percent = 100 * damage / victim_hp_max
  case dam_percent {
    _ if dam_percent <= 0 -> "annoys"
    _ if dam_percent <= 1 -> "tickles"
    _ if dam_percent <= 2 -> "nicks"
    _ if dam_percent <= 3 -> "scuffs"
    _ if dam_percent <= 4 -> "scrapes"
    _ if dam_percent <= 5 -> "scratches"
    _ if dam_percent <= 10 -> "grazes"
    _ if dam_percent <= 15 -> "injures"
    _ if dam_percent <= 20 -> "wounds"
    _ if dam_percent <= 25 -> "mauls"
    _ if dam_percent <= 30 -> "maims"
    _ if dam_percent <= 35 -> "mangles"
    _ if dam_percent <= 40 -> "mutilates"
    _ if dam_percent <= 45 -> "wrecks"
    _ if dam_percent <= 50 -> "DESTROYS"
    _ if dam_percent <= 55 -> "RAVAGES"
    _ if dam_percent <= 60 -> "TRAUMATIZES"
    _ if dam_percent <= 65 -> "CRIPPLES"
    _ if dam_percent <= 70 -> "MASSACRES"
    _ if dam_percent <= 75 -> "DEMOLISHES"
    _ if dam_percent <= 80 -> "DEVASTATES"
    _ if dam_percent <= 85 -> "PULVERIZES"
    _ if dam_percent <= 90 -> "OBLITERATES"
    _ if dam_percent <= 95 -> "ANNHILATES"
    _ if dam_percent <= 100 -> "ERADICATES"
    _ if dam_percent <= 200 -> "SLAUGHTERS"
    _ if dam_percent <= 300 -> "LIQUIFIES"
    _ if dam_percent <= 400 -> "VAPORIZES"
    _ if dam_percent <= 500 -> "ATOMIZES"
    _ -> "does UNSPEAKABLE things to"
  }
}

fn health_feedback_1p(mobile: world.MobileInternal) -> String {
  let hp_percent = 100 * mobile.hp / mobile.hp_max
  case hp_percent {
    _ if hp_percent >= 100 -> "are in excellent condition."
    _ if hp_percent >= 90 -> "have a few scratches."
    _ if hp_percent >= 75 -> "have some small wounds and bruises."
    _ if hp_percent >= 50 -> "have quite a few wounds."
    _ if hp_percent >= 30 -> "have some big nasty wounds and scratches."
    _ if hp_percent >= 15 -> "look pretty hurt."
    _ if hp_percent >= 0 -> "are in awful condition."
    _ -> "are bleeding to death."
  }
}

fn health_feedback_3p(mobile: world.Mobile) -> String {
  let hp_percent = 100 * mobile.hp / mobile.hp_max
  case hp_percent {
    _ if hp_percent >= 100 -> "is in excellent condition."
    _ if hp_percent >= 90 -> "has a few scratches."
    _ if hp_percent >= 75 -> "has some small wounds and bruises."
    _ if hp_percent >= 50 -> "has quite a few wounds."
    _ if hp_percent >= 30 -> "has some big nasty wounds and scratches."
    _ if hp_percent >= 15 -> "looks pretty hurt."
    _ if hp_percent >= 0 -> "is in awful condition."
    _ -> "is bleeding to death."
  }
}
