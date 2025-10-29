import gleam/list
import gleam/option.{None, Some}
import gleam/result
import lore/world.{
  type Direction, type ErrorRoomRequest, Closed, DoorErr, MissingDoor,
  NoChangeNeeded, Open,
}
import lore/world/event.{
  type CharacterMessage, type CharacterToRoomEvent, type Event, DoorNotifyData,
}
import lore/world/room/response

pub fn request(
  builder: response.Builder(CharacterMessage),
  event: Event(CharacterToRoomEvent, CharacterMessage),
  data: event.DoorToggleData,
) -> response.Builder(CharacterMessage) {
  let event.DoorToggleData(exit_keyword:, desired_state:) = data
  let result = {
    use exit <- result.try(find_local_exit_by_keyword(builder, exit_keyword))
    use door <- result.try(door_get(exit))
    // Is requested update valid?
    use door_id <- result.try(case door.state, desired_state {
      Open, Closed -> Ok(door.id)
      Closed, Open -> Ok(door.id)
      Open, Open -> door_error(NoChangeNeeded(Open))
      Closed, Closed -> door_error(NoChangeNeeded(Closed))
    })
    let acting_character = event.acting_character
    let world.Room(id:, ..) = response.room(builder)
    event.DoorSyncData(
      door_id:,
      from: event.from,
      from_room_id: id,
      to_room_id: exit.to_room_id,
      update: desired_state,
    )
    |> event.DoorSync
    |> event.new(from: response.self(builder), acting_character:)
    |> Ok
  }

  case result {
    Ok(door_sync) -> response.zone_event(builder, door_sync)

    Error(reason) ->
      response.reply_character(builder, event, event.ActFailed(reason))
  }
}

pub fn update(
  builder: response.Builder(a),
  event: Event(b, a),
  data: event.DoorUpdateData,
) -> response.Builder(a) {
  let event.DoorUpdateData(door_id:, update:, from_room_id:) = data
  let world.Room(id:, exits:, ..) = response.room(builder)
  let is_subject_observable = from_room_id == id

  let #(door_notifications, updated_exits) =
    list.map_fold(exits, list.new(), fn(acc, exit) {
      case exit.door {
        Some(door) if door.id == door_id -> {
          let door = world.Door(..door, state: update)
          let event =
            DoorNotifyData(exit:, update:, is_subject_observable:)
            |> event.DoorNotify

          let updated = world.RoomExit(..exit, door: Some(door))
          #([event, ..acc], updated)
        }

        _no_update -> #(acc, exit)
      }
    })

  case door_notifications != [] {
    // if there are updates
    True -> {
      let acting_character = event.acting_character
      list.fold(door_notifications, builder, fn(acc, data) {
        response.broadcast(acc, acting_character, data)
      })
      |> response.exits_update(updated_exits)
    }
    // ..else no updates
    False -> builder
  }
}

fn door_error(error: world.ErrorDoor) -> Result(a, ErrorRoomRequest) {
  Error(DoorErr(error))
}

fn door_get(exit: world.RoomExit) -> Result(world.Door, ErrorRoomRequest) {
  case exit.door {
    Some(door) -> Ok(door)
    None -> Error(DoorErr(MissingDoor(exit.keyword)))
  }
}

fn find_local_exit_by_keyword(
  builder: response.Builder(a),
  exit_keyword: world.Direction,
) -> Result(world.RoomExit, ErrorRoomRequest) {
  response.find_local_exit(builder, exit_keyword_matches(_, exit_keyword))
  |> result.replace_error(world.UnknownExit(exit_keyword))
}

fn exit_keyword_matches(room_exit: world.RoomExit, direction: Direction) -> Bool {
  room_exit.keyword == direction
}
