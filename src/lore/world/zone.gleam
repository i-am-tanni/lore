import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/otp/actor
import lore/world.{type Zone}
import lore/world/event.{type ZoneMessage, RoomToZone}
import lore/world/system_tables
import lore/world/zone/events/door_event
import lore/world/zone/events/move_event
import lore/world/zone/spawner
import lore/world/zone/zone_registry

pub type State {
  State(
    zone: Zone,
    system_tables: system_tables.Lookup,
    spawn_groups: List(world.SpawnGroup),
  )
}

pub fn start(
  zone: Zone,
  system_tables: system_tables.Lookup,
) -> Result(actor.Started(Subject(ZoneMessage)), actor.StartError) {
  actor.new_with_initialiser(100, fn(self) { init(self, zone, system_tables) })
  |> actor.on_message(recv)
  |> actor.start
}

fn init(
  self: process.Subject(ZoneMessage),
  zone: Zone,
  system_tables: system_tables.Lookup,
) -> Result(actor.Initialised(State, ZoneMessage, Subject(ZoneMessage)), String) {
  // register zone on init

  zone_registry.register(system_tables.zone, zone.id, self)

  let spawn_groups =
    list.map(zone.spawn_groups, spawner.reset_group(_, system_tables))

  State(zone:, system_tables:, spawn_groups:)
  |> actor.initialised()
  |> actor.returning(self)
  |> Ok
}

fn recv(state: State, msg: ZoneMessage) -> actor.Next(State, ZoneMessage) {
  let _ = case msg {
    RoomToZone(event) ->
      case event.data {
        event.MoveKickoff(data) ->
          move_event.call(state.system_tables, event, data)
        event.DoorSync(data) ->
          door_event.call(state.system_tables, event, data)
      }
  }

  actor.continue(state)
}
