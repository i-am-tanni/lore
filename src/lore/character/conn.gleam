//// A response builder for a request received by a character.
//// Requests can be input from the portal, events from the world, notifications
//// that the character is off-cooldown, etc.
//// 
//// The outgoing response is expressed as a list of renders, events, and 
//// updates to the character state.
//// 

import gleam/bool
import gleam/erlang/process.{type Subject, type Timer}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/set.{type Set}
import lore/character/controller.{type Controller}
import lore/character/view.{type View}
import lore/character/view/communication_view
import lore/character/view/prompt_view
import lore/server/output.{type Text}
import lore/world.{type Id, type Mobile, type Room, type StringId}
import lore/world/communication
import lore/world/event.{
  type CharacterMessage, type CharacterToRoomEvent, type Event,
}
import lore/world/system_tables

/// A type that wraps the character state and aggregates a response
/// to be returned to the calling controller.
/// 
pub opaque type Conn {
  /// action_fun is required to get around a cyclical import that I'm not smart
  /// enough to avoid at this moment.
  /// 
  Conn(
    self: process.Subject(CharacterMessage),
    character: world.MobileInternal,
    flash: Controller,
    cooldown: GlobalCooldown,
    system_tables: system_tables.Lookup,
    events: List(EventToSend),
    output: List(Text),
    actions: List(event.Action),
    publish: List(ChatData),
    update_character: Option(world.MobileInternal),
    next_controller: Option(Controller),
    reassign_endpoint: Option(Subject(event.CharacterMessage)),
    next_character: Option(world.MobileInternal),
    request_id: world.StringId(Conn),
    subscribed: Set(world.ChatChannel),
    halt: Bool,
    prompt: Bool,
    is_player: Bool,
  )
}

pub type ChatData {
  ChatData(channel: world.ChatChannel, text: String)
}

pub type CharacterInit {
  CharacterInit(mobile_id: Id(Room), room_id: Id(Room))
}

/// This is an event that is sent to another process tagged with where
/// the character wants to send it. By default, events are sent to the current
/// room, which is the sync point for actions (see event.Action type).
/// 
pub type EventToSend {
  ToRoom(event: Event(CharacterToRoomEvent, CharacterMessage))
  ToRoomId(event: Event(CharacterToRoomEvent, CharacterMessage), id: Id(Room))
  ToCharacter(
    event: event.CharacterEvent,
    to: Subject(CharacterMessage),
    acting_character: world.Mobile,
  )
}

/// On global cooldown, you can only cancel if action priority exceeds the
/// cooldown priority. Upon cancel any queued actions will be discarded in favor
/// of the requested higher priority action.
/// 
pub type GlobalCooldown {
  GlobalCooldown(
    id: StringId(event.Action),
    priority: event.Priority,
    timer: Timer,
  )
  FreeToAct
}

/// A conn is transformed into a completed response upon return.
/// 
pub type Response {
  Response(
    cooldown: GlobalCooldown,
    updated_character: Option(world.MobileInternal),
    reassign_endpoint: Option(Subject(CharacterMessage)),
    next_character: Option(world.MobileInternal),
    flash: Controller,
    next_controller: Option(Controller),
    events: List(EventToSend),
    actions: List(event.Action),
    output: List(Text),
    publish: List(ChatData),
    subscribed: Set(world.ChatChannel),
    halt: Bool,
    request_id: StringId(Conn),
  )
}

type ChannelError {
  NotFound
  ChannelOperationFailed
}

/// Generates a new conn. This is the handle generated when a request
/// is received by the character process for the purpose of building a response.
/// 
pub fn new(
  character character: world.MobileInternal,
  flash flash: Controller,
  cooldown cooldown: GlobalCooldown,
  self self: process.Subject(CharacterMessage),
  subscribed subscribed: Set(world.ChatChannel),
  system_tables system_tables: system_tables.Lookup,
) -> Conn {
  let is_player = case character.template_id {
    world.Player(_) -> True
    world.Npc(_) -> False
  }

  Conn(
    self:,
    character:,
    flash:,
    cooldown:,
    subscribed:,
    system_tables:,
    events: [],
    output: [],
    actions: [],
    publish: [],
    request_id: world.generate_id(),
    update_character: None,
    next_character: None,
    next_controller: None,
    reassign_endpoint: None,
    halt: False,
    prompt: False,
    is_player:,
  )
}

pub fn self(conn: Conn) -> Subject(CharacterMessage) {
  conn.self
}

pub fn is_player(conn: Conn) -> Bool {
  conn.is_player
}

pub fn system_tables(conn: Conn) -> system_tables.Lookup {
  conn.system_tables
}

pub fn prompt(conn: Conn) -> Conn {
  Conn(..conn, prompt: True)
}

/// Returns mobile context.
/// 
pub fn get_character(conn: Conn) -> world.MobileInternal {
  case conn.update_character {
    Some(updated_character) -> updated_character
    _ -> conn.character
  }
}

/// Stages changes to the character state.
/// 
pub fn put_character(conn: Conn, character: world.MobileInternal) -> Conn {
  Conn(..conn, update_character: Some(character))
}

pub fn next_character(conn: Conn, character: world.MobileInternal) -> Conn {
  Conn(..conn, next_character: Some(character), halt: True)
}

/// Stages a change in controller.
/// 
pub fn put_controller(conn: Conn, next: Controller) -> Conn {
  Conn(..conn, next_controller: Some(next))
}

/// This is useful if you want to puppet an NPC or switch characters.
/// 
pub fn reassign_endpoint(
  conn: Conn,
  endpoint: Subject(CharacterMessage),
) -> Conn {
  Conn(..conn, reassign_endpoint: Some(endpoint))
}

/// Returns controller flash memory
/// 
pub fn get_flash(conn: Conn) -> Controller {
  conn.flash
}

/// Updates the current flash memory for the current controller.
/// Fails if the controller received is not the same kind as the current
/// controller.
/// 
pub fn put_flash(conn: Conn, flash: Controller) -> Result(Conn, Nil) {
  case controller.is_same_kind(conn.flash, flash) {
    True -> Ok(Conn(..conn, flash: flash))
    False -> Error(Nil)
  }
}

/// Renders text without a newline.
/// 
pub fn render(conn: Conn, view: View) -> Conn {
  let text = output.Text(text: view.to_string_tree(view), newline: False)
  Conn(..conn, output: [text, ..conn.output])
}

/// Renders text with a newline.
/// 
pub fn renderln(conn: Conn, view: View) -> Conn {
  let text = output.Text(text: view.to_string_tree(view), newline: True)
  Conn(..conn, output: [text, ..conn.output])
}

/// Notifies the process owner to terminate at the end of the response.
/// 
pub fn terminate(conn: Conn) -> Conn {
  Conn(..conn, halt: True)
}

/// Send an event to the room.
/// 
pub fn event(conn: Conn, event: CharacterToRoomEvent) -> Conn {
  let event =
    event.new(
      from: conn.self,
      acting_character: trim_character(conn.character),
      data: event,
    )

  Conn(..conn, events: [ToRoom(event), ..conn.events])
}

/// An extension of a room event where the data is sent directly back to the 
/// acting_character subject. E.g. upon looking at a character, the victim will
/// send the actor its long description directly to avoid unnecessary copying.
/// 
pub fn character_event(
  conn: Conn,
  event: event.CharacterEvent,
  send to: Subject(CharacterMessage),
) -> Conn {
  let acting_character = trim_character(get_character(conn))
  let event = ToCharacter(event:, to:, acting_character:)
  Conn(..conn, events: [event, ..conn.events])
}

/// If more than one action is required, it is recommended to use `conn.actions`
/// instead of piping a series of `.action()` as that will be more efficient.
/// 
pub fn action(conn: Conn, action: event.Action) -> Conn {
  case conn.actions {
    [] -> Conn(..conn, actions: [action])
    // An append was chosen here rather than prepending + reversing  
    // at the end of the response because more often than not
    // you're either adding one action or one group once per response.
    //
    // The most frequent case of adding a list of actions is
    // when the character comes off cooldown and attempts to consume their 
    // actions backlog. Prepends would result in a lot of unnecessary list 
    // reversing for action queue processing.
    // 
    actions -> Conn(..conn, actions: list.append([action], actions))
  }
}

/// Adds a list of actions for processing.
/// 
pub fn actions(conn: Conn, actions: List(event.Action)) -> Conn {
  case conn.actions {
    [] -> Conn(..conn, actions: actions)
    queue -> Conn(..conn, actions: list.append(queue, actions))
  }
}

/// Requests use of an exit.
/// 
pub fn move_request(conn: Conn, exit_keyword: world.Direction) -> Conn {
  event(conn, event.MoveRequest(exit_keyword:))
}

/// Spawns a character into a room.
/// 
pub fn spawn(conn: Conn, to to_room_id: Id(Room)) -> Conn {
  let character = conn.character
  case to_room_id == character.room_id {
    True -> {
      let data =
        event.MoveArriveData(from_room_id: None, from_exit_keyword: None)
      let event =
        event.new(
          from: conn.self,
          acting_character: trim_character(character),
          data: event.MoveArrive(data),
        )
      Conn(..conn, events: [ToRoom(event:), ..conn.events])
    }

    // .. else fix the room_id on the character to match
    False -> {
      let data =
        event.MoveArriveData(from_room_id: None, from_exit_keyword: None)
      let update = world.MobileInternal(..character, room_id: to_room_id)
      let event =
        event.new(
          from: conn.self,
          acting_character: trim_character(update),
          data: event.MoveArrive(data),
        )
      let events = [ToRoom(event:), ..conn.events]
      Conn(..conn, update_character: Some(update), events:)
    }
  }
}

/// Subscribe to a chat channel.
///
pub fn subscribe(conn: Conn, channel: world.ChatChannel) -> Conn {
  let result = {
    use <- bool.guard(set.contains(conn.subscribed, channel), Error(NotFound))
    let comms = conn.system_tables.communication
    use <- bool.guard(
      !communication.subscribe_chat(comms, channel, conn.self),
      Error(ChannelOperationFailed),
    )
    Ok(Conn(..conn, subscribed: set.insert(conn.subscribed, channel)))
  }

  case result {
    Ok(conn) -> renderln(conn, communication_view.subscribe_success(channel))
    Error(NotFound) ->
      renderln(conn, communication_view.already_subscribed(channel))
    Error(ChannelOperationFailed) ->
      renderln(conn, communication_view.subscribe_fail(channel))
  }
}

/// Unsubscribe from a chat channel
///
pub fn unsubscribed(conn: Conn, channel: world.ChatChannel) -> Conn {
  let result = {
    use <- bool.guard(!set.contains(conn.subscribed, channel), Error(NotFound))
    let comms = conn.system_tables.communication
    use <- bool.guard(
      !communication.unsubscribe_chat(comms, channel, conn.self),
      Error(ChannelOperationFailed),
    )
    Ok(Conn(..conn, subscribed: set.delete(conn.subscribed, channel)))
  }

  case result {
    Ok(conn) -> renderln(conn, communication_view.subscribe_success(channel))
    Error(NotFound) ->
      renderln(conn, communication_view.already_unsubscribed(channel))
    Error(ChannelOperationFailed) ->
      renderln(conn, communication_view.unsubscribe_fail(channel))
  }
}

pub fn publish(conn: Conn, channel: world.ChatChannel, text: String) -> Conn {
  let data = ChatData(channel:, text:)
  Conn(..conn, publish: [data, ..conn.publish])
}

pub fn is_subscribed(conn: Conn, channel: world.ChatChannel) -> Bool {
  set.contains(conn.subscribed, channel)
}

/// Transforms a conn into a completed response to be processed by the caller.
/// 
pub fn to_response(conn: Conn) -> Response {
  let conn = case conn.actions {
    [] -> conn
    actions -> process_actions(conn, actions)
  }

  // Append output with prompt if applicable.
  let output = case conn.prompt {
    True -> {
      let newline =
        view.blank()
        |> view.to_string_tree
        |> output.Text(text: _, newline: True)

      let prompt =
        prompt_view.prompt()
        |> view.to_string_tree
        |> output.Text(text: _, newline: False)

      [prompt, newline, ..conn.output]
    }

    False -> conn.output
  }

  Response(
    cooldown: conn.cooldown,
    updated_character: conn.update_character,
    reassign_endpoint: conn.reassign_endpoint,
    next_character: conn.next_character,
    flash: conn.flash,
    next_controller: conn.next_controller,
    events: list.reverse(conn.events),
    output: list.reverse(output),
    publish: list.reverse(conn.publish),
    subscribed: conn.subscribed,
    actions: conn.actions,
    halt: conn.halt,
    request_id: conn.request_id,
  )
}

// Convert actions to events if they can be performed. Stash the remainder.
fn process_actions(conn: Conn, actions: List(event.Action)) -> Conn {
  case actions {
    [next, ..rest] ->
      case can_act(conn.cooldown, next) {
        True ->
          case perform(conn, next) {
            Ok(conn) -> process_actions(conn, rest)
            // In the case of being able to act BUT failing the conditions, 
            // clear the action queue and cancel any active global cooldown.
            Error(_reason) -> Conn(..conn, actions: [], cooldown: FreeToAct)
          }

        // ..else if the character cannot act, append the action queue
        False -> Conn(..conn, actions: actions)
      }

    [] -> Conn(..conn, actions: [])
  }
}

fn perform(conn: Conn, action: event.Action) -> Result(Conn, String) {
  // First, cancel any existing cooldown timer if one exists.
  case conn.cooldown {
    GlobalCooldown(timer:, ..) -> {
      process.cancel_timer(timer)
      Nil
    }
    FreeToAct -> Nil
  }

  // Then try to run the action
  use _ <- result.try(action.condition(conn.character))
  let conn = event(conn, action.event)
  // If the action succeeds, schedule the next global cooldown timer

  case action.delay {
    delay if delay <= 0 -> Conn(..conn, cooldown: FreeToAct)
    // if delay is > 0, schedule a cooldown expiration notification to self
    delay -> {
      let event.Action(id:, priority:, ..) = action
      let timer =
        process.send_after(conn.self, delay, event.CooldownExpired(id:))

      Conn(..conn, cooldown: GlobalCooldown(id:, priority:, timer:))
    }
  }
  |> Ok
}

// Character can act if either:
// - FreeToAct
// - the requested action's priority exceeds cooldown's priority level
fn can_act(cooldown: GlobalCooldown, action: event.Action) -> Bool {
  case cooldown {
    FreeToAct -> True
    GlobalCooldown(priority:, ..) ->
      event.is_priority_gt(action.priority, priority)
  }
}

/// This prevents leaking private character information via events.
/// 
fn trim_character(character: world.MobileInternal) -> Mobile {
  let world.MobileInternal(
    id:,
    room_id:,
    template_id:,
    name:,
    keywords:,
    pronouns:,
    short:,
    ..,
  ) = character

  world.Mobile(id:, room_id:, template_id:, name:, keywords:, pronouns:, short:)
}
