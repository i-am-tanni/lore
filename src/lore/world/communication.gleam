//// A pub-sub system publishing events to subscibers. These can range from
//// chat channels to room channels. 
//// Events can be any events. Not just communication events.
//// Subjects are monitored so that a crash results in the subject information
//// being automatically cleaned up.
//// 

import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/otp/actor
import gleam/result
import gleam/string
import glets/table
import lore/world.{type Id, type Mobile, type Room}
import lore/world/event

/// A communication channel will push events to all subscribers.
/// 
pub type Channel {
  /// The main chat channel for out-of-character communication.
  ///
  Chat(world.ChatChannel)
  /// The channel of the room for publishing in-room events.
  ///
  RoomChannel(Id(Room))
  /// A private channel for an individual player to receive direct messages
  /// or whispers.
  ///
  DirectMessage(Id(Mobile))
}

/// Messages to be received by the channel process for the purpose of 
/// serializing writes.
/// 
pub type Message {
  /// Subscribing is performed as a call to avoid race conditions with
  /// publishing in room channels.
  /// 
  Subscribe(caller: Subject(Bool), channel: Channel, subscriber: Subscriber)

  /// Unsubscribing is performed as a call to avoid race conditions with
  /// publishing in room channels.
  /// 
  Unsubscribe(caller: Subject(Bool), channel: Channel, subscriber: Subscriber)

  /// Drops the pid entirely from the table and tracking.
  /// This occurs if the subscriber shuts down nomrally or crashes.
  /// So it's basically an automatic cleanup.
  Drop(process.Pid)
}

type State {
  State(
    table: table.Set(Channel, List(Subscriber)),
    monitors: Dict(process.Pid, process.Monitor),
    subscriptions: Dict(process.Pid, List(Channel)),
  )
}

/// A mailbox for published events to receive events from the channel subscribed
/// 
pub type Subscriber {
  Mobile(subject: Subject(event.CharacterMessage))
}

/// Start the pub-sub.
pub fn start(
  table_name: process.Name(Message),
) -> Result(actor.Started(Subject(Message)), actor.StartError) {
  actor.new_with_initialiser(1000, init(_, table_name))
  |> actor.named(table_name)
  |> actor.on_message(recv)
  |> actor.start
}

// We use an init here to add a selector for downed process monitoring.
// 
fn init(
  self: process.Subject(Message),
  table_name: process.Name(Message),
) -> Result(actor.Initialised(State, Message, process.Subject(Message)), String) {
  let start_table =
    table_name
    |> table.new
    |> table.set
    |> result.replace_error(
      "Failed to start ets table: " <> string.inspect(table_name),
    )

  use table <- result.try(start_table)

  // If subscriber exits or crashes, monitor in order to drop pid from tables.
  // This prevents a memory leak over time as dead mailboxes accumulate.
  let selector =
    process.new_selector()
    |> process.select_monitors(fn(monitor) {
      let assert process.ProcessDown(pid:, ..) = monitor
      Drop(pid)
    })
    |> process.select(self)

  State(table: table, monitors: dict.new(), subscriptions: dict.new())
  |> actor.initialised()
  |> actor.selecting(selector)
  |> actor.returning(self)
  |> Ok
}

pub fn subscribe(
  table_name: process.Name(Message),
  channel: Channel,
  subscriber: Subscriber,
) -> Bool {
  let subject = process.named_subject(table_name)
  process.call(subject, 1000, Subscribe(caller: _, channel:, subscriber:))
}

pub fn unsubscribe(
  table_name: process.Name(Message),
  channel: Channel,
  subscriber: Subscriber,
) -> Bool {
  let subject = process.named_subject(table_name)
  process.call(subject, 1000, Unsubscribe(caller: _, channel:, subscriber:))
}

pub fn subscribe_chat(
  table_name: process.Name(Message),
  chat_channel: world.ChatChannel,
  subscriber: Subject(event.CharacterMessage),
) -> Bool {
  let subject = process.named_subject(table_name)
  process.call(subject, 1000, Subscribe(
    caller: _,
    channel: Chat(chat_channel),
    subscriber: Mobile(subscriber),
  ))
}

pub fn unsubscribe_chat(
  table_name: process.Name(Message),
  channel: world.ChatChannel,
  subscriber: Subject(event.CharacterMessage),
) -> Bool {
  let subject = process.named_subject(table_name)
  process.call(subject, 1000, Unsubscribe(
    caller: _,
    channel: Chat(channel),
    subscriber: Mobile(subscriber),
  ))
}

/// Publishes a message to a channel's subscribers.
/// The lookup occurs inside the caller.
/// 
pub fn publish(
  table_name: process.Name(Message),
  channel: Channel,
  message: event.CharacterMessage,
) -> Nil {
  table.lookup(table_name, channel)
  |> result.unwrap([])
  |> list.each(fn(subscriber) {
    case subscriber {
      Mobile(subject:) -> process.send(subject, message)
    }
  })
}

/// Publish a message to a chat channel.
/// 
pub fn publish_chat(
  table_name: process.Name(Message),
  channel: world.ChatChannel,
  username: String,
  text: String,
) -> Nil {
  let data = event.ChatData(channel:, username:, text:)

  table.lookup(table_name, Chat(channel))
  |> result.unwrap([])
  |> list.each(fn(subscriber) {
    case subscriber {
      Mobile(subject:) -> process.send(subject, event.Chat(data))
    }
  })
}

pub fn is_subscribed(
  table_name: process.Name(Message),
  channel: Channel,
  subscriber: Subscriber,
) -> Bool {
  table.lookup(table_name, channel)
  |> result.unwrap([])
  |> list.contains(subscriber)
}

// Private

fn recv(state: State, msg: Message) -> actor.Next(State, Message) {
  let state = case handle_message(state, msg) {
    Ok(update) -> update
    Error(Nil) -> state
  }

  actor.continue(state)
}

fn handle_message(state: State, msg: Message) -> Result(State, Nil) {
  case msg {
    Subscribe(caller:, channel:, subscriber:) -> {
      let State(table:, monitors:, subscriptions:) = state
      use pid <- result.try(process.subject_owner(subscriber.subject))

      // check if pid is known to the actor
      let monitors = case dict.has_key(monitors, pid) {
        // .. and do nothing if known
        True -> monitors
        False -> {
          // ..but if this is a new pid subscribing, add monitoring for
          //   later clean up when mailbox shuts down.
          dict.insert(monitors, pid, process.monitor(pid))
        }
      }

      let subscriptions =
        dict.get(subscriptions, pid)
        |> result.unwrap([])
        |> list.prepend(channel)
        |> dict.insert(subscriptions, pid, _)

      table
      |> table.lookup(channel)
      |> result.unwrap([])
      |> list.prepend(subscriber)
      |> table.insert(table, channel, _)

      process.send(caller, True)

      Ok(State(table:, monitors:, subscriptions:))
    }

    // Unsubscribe from a channel
    Unsubscribe(caller:, channel:, subscriber:) -> {
      let State(table:, subscriptions:, ..) = state
      use pid <- result.try(process.subject_owner(subscriber.subject))
      let subscriptions =
        dict.get(subscriptions, pid)
        |> result.unwrap([])
        |> list.filter(fn(x) { channel != x })
        |> dict.insert(subscriptions, pid, _)

      table
      |> table.lookup(channel)
      |> result.unwrap([])
      |> list.filter(fn(subscriber) { !is_pid_match(subscriber, pid) })
      |> table.insert(table, channel, _)

      process.send(caller, True)

      Ok(State(..state, subscriptions:))
    }

    // Automatic cleanup for when a subscriber mailbox exits
    Drop(pid) -> {
      // First, get channel list that the subscriber is subscribed to
      let State(table:, monitors:, subscriptions:) = state
      use monitor <- result.try(dict.get(monitors, pid))
      use channels <- result.try(dict.get(subscriptions, pid))
      // ..then for each channel drop the subscriber info
      list.each(channels, fn(channel) {
        channel
        |> table.lookup(table, _)
        |> result.unwrap([])
        |> list.filter(fn(subscriber) { !is_pid_match(subscriber, pid) })
        |> table.insert(table, channel, _)
      })
      // ..and deactivate monitoring
      process.demonitor_process(monitor)
      // Finally delete tracking info related to the pid
      let monitors = dict.delete(monitors, pid)
      let subscriptions = dict.delete(subscriptions, pid)
      Ok(State(..state, monitors:, subscriptions:))
    }
  }
}

fn is_pid_match(subscriber: Subscriber, pid: process.Pid) -> Bool {
  case process.subject_owner(subscriber.subject) {
    Ok(x) -> pid == x
    _ -> False
  }
}
