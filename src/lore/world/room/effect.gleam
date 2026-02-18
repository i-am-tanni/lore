//// Side effects rooms can perform, represented as data and
//// triggered via the realize() function at the room boundary

import gleam/erlang/process.{type Subject}
import gleam/list
import lore/character/character_registry
import lore/character/view.{type View}
import lore/server/output
import lore/world.{type Mobile, type StringId}
import lore/world/communication.{RoomChannel}
import lore/world/event.{
  type CharacterEvent, type CharacterMessage, type RoomMessage, type ZoneEvent,
  Event,
}
import lore/world/named_actors
import lore/world/zone/zone_registry

/// A side-effect that a room can perform, represented as data.
///
pub type RoomEffect(msg) {
  /// Reply to the author of an event asychronously.
  ///
  Send(to: Subject(msg), message: msg)

  /// Render text to a subject.
  ///
  Render(subject: Subject(CharacterMessage), text: output.Text)

  /// A text render with side-effects.
  ///
  RenderLazy(
    subject: Subject(CharacterMessage),
    view_fun: fn() -> View,
    newline: Bool,
  )

  /// Send text output to a character subject
  ///
  ToCharacter(subject: Subject(CharacterMessage), event: CharacterEvent)

  /// Send an event to an individual character when the subject is unknown
  ///
  ToCharacterId(id: StringId(Mobile), event: CharacterEvent)

  /// Broadcast an event to all subscribers in the room channel
  ///
  Broadcast(event: CharacterEvent)

  /// A subscription to channel messages
  ///
  Subscribe(subscriber: communication.Subscriber)

  /// Unsubscribe from channel messages
  ///
  Unsubscribe(subscriber: communication.Subscriber)

  /// Send an event to the zone.
  ///
  ToZone(event: event.ZoneEvent)

  ///
  Batch(List(RoomEffect(msg)))

  /// A generic lazy effect
  Lazy(fn() -> Nil)

  // No effect
  EffectNone
}

pub fn send(to: Subject(a), message: a) -> RoomEffect(a) {
  Send(to:, message:)
}

pub fn send_zone(event: ZoneEvent) -> RoomEffect(a) {
  ToZone(event)
}

pub fn send_character_id(
  recipient: world.StringId(Mobile),
  event: CharacterEvent,
) -> RoomEffect(a) {
  ToCharacterId(id: recipient, event:)
}

pub fn send_character(
  subject: Subject(CharacterMessage),
  event: CharacterEvent,
) -> RoomEffect(a) {
  ToCharacter(subject:, event:)
}

pub fn broadcast(event: CharacterEvent) -> RoomEffect(a) {
  Broadcast(event:)
}

pub fn room_subscribe(subscriber: Subject(CharacterMessage)) -> RoomEffect(a) {
  Subscribe(communication.Mobile(subscriber))
}

pub fn room_unsubscribe(subscriber: Subject(CharacterMessage)) -> RoomEffect(a) {
  Unsubscribe(communication.Mobile(subscriber))
}

/// Render text to a subject with a newline.
///
pub fn renderln(subject: Subject(CharacterMessage), view: View) -> RoomEffect(a) {
  Render(
    subject:,
    text: output.Text(text: view.to_string_tree(view), newline: True),
  )
}

/// Render text to a subject without a newline.
///
pub fn render(subject: Subject(CharacterMessage), view: View) -> RoomEffect(a) {
  Render(
    subject:,
    text: output.Text(text: view.to_string_tree(view), newline: False),
  )
}

/// Render text to a subject with a newline lazily.
///
pub fn renderln_lazy(
  subject: Subject(CharacterMessage),
  view_fun: fn() -> View,
) -> RoomEffect(a) {
  RenderLazy(subject:, view_fun:, newline: True)
}

/// Render text to a subject without a newline lazily.
///
pub fn render_lazy(
  subject: Subject(CharacterMessage),
  view_fun: fn() -> View,
) -> RoomEffect(a) {
  RenderLazy(subject:, view_fun:, newline: False)
}

pub fn batch(list: List(RoomEffect(a))) -> RoomEffect(a) {
  Batch(list)
}

pub fn lazy(lazy_fun: fn() -> Nil) -> RoomEffect(a) {
  Lazy(lazy_fun)
}

/// Realize a room side-effect.
///
pub fn realize(
  effect: RoomEffect(a),
  from self: process.Subject(RoomMessage),
  by acting_character: world.Mobile,
  in room: world.Room,
  with_context lookup: named_actors.Lookup,
) -> Nil {
  case effect {
    Send(to:, message:) -> process.send(to, message)

    Render(subject:, text:) ->
      event.RoomSentText(text: [text])
      |> event.RoomSent(room.id)
      |> process.send(subject, _)

    RenderLazy(subject:, view_fun:, newline:) ->
      view_fun()
      |> view.to_string_tree
      |> output.Text(text: _, newline:)
      |> list.wrap
      |> event.RoomSentText
      |> event.RoomSent(room.id)
      |> process.send(subject, _)

    ToCharacter(subject:, event:) ->
      Event(from: self, acting_character:, data: event)
      |> event.RoomToCharacter
      |> event.RoomSent(room.id)
      |> process.send(subject, _)

    ToCharacterId(id:, event:) ->
      case character_registry.whereis(lookup.character, id) {
        Ok(subject) ->
          Event(from: self, acting_character:, data: event)
          |> event.RoomToCharacter
          |> event.RoomSent(room.id)
          |> process.send(subject, _)

        Error(_) -> Nil
      }

    ToZone(event:) ->
      case zone_registry.whereis(lookup.zone, room.zone_id) {
        Ok(subject) ->
          Event(from: self, acting_character:, data: event)
          |> event.RoomToZone
          |> process.send(subject, _)

        Error(_) -> Nil
      }

    Broadcast(event:) ->
      Event(from: self, acting_character:, data: event)
      |> event.RoomToCharacter
      |> event.RoomSent(room.id)
      |> communication.publish(lookup.communication, RoomChannel(room.id), _)

    // Warning! Blocks until the table is up-to-date to keep the table in sync
    // for broadcasts.
    Subscribe(subscriber:) -> {
      communication.subscribe(
        lookup.communication,
        RoomChannel(room.id),
        subscriber,
      )
      Nil
    }

    // Warning! Blocks until the table is up-to-date to keep the table in sync
    // for broadcasts.
    Unsubscribe(subscriber:) -> {
      communication.unsubscribe(
        lookup.communication,
        RoomChannel(room.id),
        subscriber,
      )
      Nil
    }

    Lazy(lazy_effect) -> lazy_effect()

    EffectNone -> Nil

    Batch(effects) ->
      list.each(effects, realize(_, self, acting_character, room, lookup))
  }
}
