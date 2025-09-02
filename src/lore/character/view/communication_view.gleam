import gleam/bit_array
import gleam/option.{type Option, None, Some}
import lore/character/pronoun
import lore/character/view.{type View}
import lore/character/view/character_view
import lore/world
import lore/world/event

type Self {
  Self
  NotSelf
}

type CommunicationVerb {
  Say
  Ask
  Exclaim
}

pub fn notify(
  self: world.MobileInternal,
  acting_character: world.Mobile,
  data: event.CommunicationData,
) -> View {
  let self_id = self.id
  let is_acting_character = self_id == acting_character.id

  case data {
    event.Say(text:, adverb:) if is_acting_character -> [
      "You ",
      adverb_to_string(adverb),
      verb(text, Self),
      ", \"",
      text,
      "\"",
    ]

    event.Say(text:, adverb:) -> [
      character_view.name(acting_character),
      " ",
      adverb_to_string(adverb),
      verb(text, NotSelf),
      ", \"",
      text,
      "\"",
    ]

    event.SayAt(text:, at:, adverb:) if is_acting_character && self_id == at.id -> [
      "You ",
      adverb_to_string(adverb),
      "mutter to yourself, \"",
      text,
      "\"",
    ]

    event.SayAt(text:, at:, adverb:) if is_acting_character -> [
      "You ",
      adverb_to_string(adverb),
      verb_to(text, Self),
      " ",
      character_view.name(at),
      ", \"",
      text,
      "\"",
    ]

    event.SayAt(text:, at:, adverb:) if acting_character.id == at.id -> [
      character_view.name(acting_character),
      adverb_to_string(adverb),
      " mutters to ",
      pronoun_self(acting_character),
      ", \"",
      text,
      "\"",
    ]

    event.SayAt(text:, at:, adverb:) if self_id == at.id -> [
      character_view.name(acting_character),
      " ",
      adverb_to_string(adverb),
      verb_to(text, NotSelf),
      " you, \"",
      text,
      "\"",
    ]

    event.SayAt(text:, at:, adverb:) -> {
      let acting_character = character_view.name(acting_character)
      let victim = character_view.name(at)
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
    }

    event.Whisper(text:, at:) if is_acting_character && self_id == at.id -> [
      "You whisper to yourself, \"",
      text,
      "\"",
    ]

    event.Whisper(text:, at:) if is_acting_character -> [
      "You whisper to ",
      character_view.name(at),
      ", \"",
      text,
      "\"",
    ]

    event.Whisper(text:, at:) if self_id == at.id -> [
      character_view.name(acting_character),
      " whispers in your ear, \"",
      text,
      "\"",
    ]

    event.Whisper(at:, ..) -> {
      let acting_character = character_view.name(acting_character)
      let victim = character_view.name(at)
      [acting_character, " whispers something to ", victim, "."]
    }

    event.Emote(text:) -> [character_view.name(acting_character), " ", text]
  }
  |> view.Leaves
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

pub fn empty() -> View {
  "What do you want to say?"
  |> view.Leaf
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
  let pronoun.Pronoun(himself:, ..) = pronoun.lookup(acting_character.pronouns)
  himself
}

fn adverb_to_string(adverb: Option(String)) -> String {
  case adverb {
    Some(adverb) -> adverb <> " "
    None -> ""
  }
}
