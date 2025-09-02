import gleam/erlang/process
import gleam/result
import lore/world
import lore/world/event.{
  type Done, type Event, type RoomMessage, type ZoneEvent, Done,
}
import lore/world/room/room_registry
import lore/world/system_tables

pub fn call(
  system_tables: system_tables.Lookup,
  event: Event(ZoneEvent, RoomMessage),
  data: event.DoorSyncData,
) -> Nil {
  let event.DoorSyncData(door_id:, to_room_id:, from_room_id:, update:, from:) =
    data

  let result = {
    let lookup =
      room_registry.whereis(system_tables.room, to_room_id)
      |> result.replace_error(world.RoomLookupFailed(to_room_id))

    use to_room_subject <- result.try(lookup)
    let door_update_data =
      event.DoorUpdateData(door_id:, update:, from_room_id:)
    let Done = process.call(event.from, 1000, begin(_, event, door_update_data))
    Ok(process.send(to_room_subject, end(from, event, door_update_data)))
  }

  case result {
    Ok(_) -> Nil
    Error(reason) -> process.send(data.from, abort(event, reason, data))
  }
}

fn begin(
  self: process.Subject(Done),
  event: Event(ZoneEvent, RoomMessage),
  data: event.DoorUpdateData,
) -> RoomMessage {
  let acting_character = event.acting_character
  let data = event.DoorUpdateBegin(data)
  let event = event.new(from: self, acting_character: acting_character, data:)
  event.InterRoom(event)
}

fn end(
  from: process.Subject(event.CharacterMessage),
  event: Event(ZoneEvent, RoomMessage),
  data: event.DoorUpdateData,
) -> RoomMessage {
  let acting_character = event.acting_character
  let data = event.DoorUpdateEnd(data)
  let event = event.new(from:, acting_character:, data:)
  event.CharacterToRoom(event)
}

fn abort(
  event: Event(ZoneEvent, RoomMessage),
  reason: world.ErrorRoomRequest,
  data: event.DoorSyncData,
) -> event.CharacterMessage {
  let event.DoorSyncData(from_room_id:, ..) = data
  let event.Event(from:, acting_character:, ..) = event

  event.new(from:, acting_character:, data: event.ActFailed(reason))
  |> event.RoomToCharacter
  |> event.RoomSent(from: from_room_id)
}
