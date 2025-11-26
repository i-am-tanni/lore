import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/otp/actor
import gleam/result.{try}
import lore/world.{type Id, type SpawnGroup, type Zone}
import lore/world/event.{type ZoneMessage, ResetSpawnGroup, RoomToZone}
import lore/world/system_tables
import lore/world/zone/events/door_event
import lore/world/zone/events/move_event
import lore/world/zone/spawner
import lore/world/zone/zone_registry

pub type State {
  State(
    self: process.Subject(ZoneMessage),
    zone: Zone,
    system_tables: system_tables.Lookup,
    spawn_groups: Dict(Id(SpawnGroup), SpawnGroup),
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
    list.map(zone.spawn_groups, fn(group) {
      let group = spawner.reset_group(group, system_tables)
      let _ = schedule_next_reset(self, group)
      #(group.id, group)
    })
    |> dict.from_list

  State(self:, zone:, system_tables:, spawn_groups:)
  |> actor.initialised()
  |> actor.returning(self)
  |> Ok
}

fn recv(state: State, msg: ZoneMessage) -> actor.Next(State, ZoneMessage) {
  let state = case msg {
    RoomToZone(event) ->
      case event.data {
        event.MoveKickoff(data) -> {
          move_event.call(state.system_tables, event, data)
          state
        }
        event.DoorSync(data) -> {
          door_event.call(state.system_tables, event, data)
          state
        }
      }

    ResetSpawnGroup(group_id) -> reset_spawn_group(state, group_id)
  }

  actor.continue(state)
}

fn reset_spawn_group(state: State, group_id: Id(SpawnGroup)) -> State {
  let spawn_groups = state.spawn_groups
  let result = {
    use group <- try(dict.get(spawn_groups, group_id))
    let group = spawner.reset_group(group, state.system_tables)
    let _ = schedule_next_reset(state.self, group)

    Ok(dict.insert(spawn_groups, group_id, group))
  }

  case result {
    Ok(update) -> State(..state, spawn_groups: update)
    Error(_) -> state
  }
}

fn schedule_next_reset(
  self: process.Subject(ZoneMessage),
  group: SpawnGroup,
) -> Result(process.Timer, Nil) {
  case group.is_enabled {
    True ->
      Ok(process.send_after(
        self,
        group.reset_freq * 1000,
        ResetSpawnGroup(group.id),
      ))

    False -> Error(Nil)
  }
}
