//// A pub-sub system publishing events to subscibers. These can range from
//// chat channels or channels for room events, etc.
////

import carpenter/table
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/otp/actor
import gleam/result
import ming/server/cache
import ming/world.{type Mobile, type RoomEvent}
import ming/world/id.{type Id}

const table_name = "channels"

/// A channel will push events to all subscribers.
/// 
pub type Channel {
  /// The main chat channel for out-of-character communication.
  ///
  General
  /// The channel of the room for publishing in-room events.
  ///
  RoomChannel(Id(world.Room))
  /// A private channel for an individual player to receive direct messages
  /// or whispers.
  ///
  DirectMessage(Id(Mobile))
}

/// A mailbox for published events to be sent to members of the channel
/// 
pub type Subscriber {
  MobSub(id: Id(Mobile), subject: Subject(world.CharacterMessage))
  RoomSub(id: Id(world.Room), subject: Subject(RoomEvent))
}

pub type SubscriberId {
  MobSubId(Id(Mobile))
  RoomSubId(Id(world.Room))
}

/// Messages that effect channel state.
/// 
pub type Message(a) {
  Subscribe(channel: Channel, subscriber: Subscriber)
  Unsubscribe(channel: Channel, id: SubscriberId)
  AddChannels(channels: List(Channel))
  AddChannel(channel: Channel)
}

pub fn start_pubsub() -> Result(Subject(Message(a)), actor.StartError) {
  cache.start(table_name, recv)
}

fn recv(
  msg: Message(a),
  state: table.Set(Channel, List(Subscriber)),
) -> actor.Next(Message(a), table.Set(Channel, List(Subscriber))) {
  case msg {
    Subscribe(channel:, subscriber:) -> subscribe(state, channel, subscriber)
    Unsubscribe(channel:, id:) -> unsubscribe(state, channel, id)
    AddChannel(channel:) -> table.insert(state, [#(channel, [])])
    AddChannels(channels:) ->
      channels
      |> list.map(fn(channel) { #(channel, []) })
      |> table.insert(state, _)
  }
  actor.continue(state)
}

/// Subscribe to a channel.
/// 
fn subscribe(
  state: table.Set(Channel, List(Subscriber)),
  channel: Channel,
  subscriber: Subscriber,
) -> Nil {
  let updated_subs =
    cache.lookup(table_name, key: channel)
    |> result.unwrap([])
    |> list.prepend(subscriber)

  table.insert(state, [#(channel, updated_subs)])
}

/// Unsubscribe from a channel.
/// 
pub fn unsubscribe(
  table: table.Set(Channel, List(Subscriber)),
  channel: Channel,
  id: SubscriberId,
) -> Nil {
  // reject the subscriber id of the member who wishes to unsubscribe
  let updated =
    cache.lookup(table_name, key: channel)
    |> result.unwrap([])
    |> list.filter(fn(subscriber) {
      case id, subscriber {
        MobSubId(mob_id), MobSub(id:, ..) -> mob_id != id
        RoomSubId(room_id), RoomSub(id:, ..) -> room_id != id
        _, _ -> True
      }
    })

  table.insert(table, [#(channel, updated)])
}

/// Publish an event. 
/// If a subscriber is a room, publish in that room's channel as well.
/// 
pub fn publish(channel: Channel, msg: world.CharacterMessage) -> Nil {
  cache.lookup(table_name, channel)
  |> result.unwrap([])
  |> list.each(fn(subscriber) {
    case subscriber {
      MobSub(subject:, ..) -> actor.send(subject, msg)
      RoomSub(id:, ..) -> publish(RoomChannel(id), msg)
    }
  })
}
