import gleam/bool
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/function.{identity}
import gleam/list
import ming/server/lib
import ming/world.{type CharacterMessage, type MobTemplate, type Room, type Zone}
import ming/world/id.{type Id, Id}
import ming/world/item.{type Item, type ItemInstance}
import pog

pub type State {
  State(groups: Dict(Id(SpawnGroup), SpawnGroup))
}

pub type SpawnGroup {
  SpawnGroup(
    id: Id(SpawnGroup),
    name: String,
    zone_id: Id(Zone),
    is_enabled: Bool,
    reset_frequency: Int,
    members: Dict(Id(Spawn), Spawn),
  )
}

pub type Spawn {
  /// Holds state and template data for the spawner as well as the spawn rules
  /// - TemplateId answers the question what to spawn
  /// - RoomIds and SpawnStrategy answers the question where to spawn
  /// - Min_spawns, max_spawns, probability answer the question of how many to 
  /// spawn
  /// - Spawn_frequency answers the question of when to spawn
  /// 
  /// 
  SpawnMobile(
    id: Id(Spawn),
    template_id: Id(MobTemplate),
    instances: List(SpawnInstance),
    is_despawn_on_reset: Bool,
    min_spawns: Int,
    max_spawns: Int,
    spawn_frequency: Int,
    strategy: SpawnStrategy,
    spawn_probability: Int,
    room_ids: List(Id(Room)),
    round_robin_tail: List(Id(Room)),
  )
}

pub type SpawnInstance {
  MobInstance(Subject(CharacterMessage))
  ItemInstance(Id(ItemInstance))
}

pub type SpawnError {
  QueryError(pog.QueryError)
}

pub type SpawnStrategy {
  Random
  RoundRobin
}

pub fn reset_all(
  groups: Dict(Id(SpawnGroup), SpawnGroup),
) -> Dict(Id(SpawnGroup), SpawnGroup) {
  list.map(dict.to_list(groups), fn(pair) {
    let #(group_id, group) = pair
    #(group_id, reset_group(group))
  })
  |> dict.from_list()
}

pub fn reset_group(group: SpawnGroup) -> SpawnGroup {
  use <- bool.guard(!group.is_enabled, group)
  let members =
    {
      use #(spawn_id, spawn_data) <- list.map(dict.to_list(group.members))
      #(spawn_id, reset_instances(spawn_data))
    }
    |> dict.from_list()

  SpawnGroup(..group, members: members)
}

fn reset_instances(spawn: Spawn) -> Spawn {
  let SpawnMobile(instances:, is_despawn_on_reset:, min_spawns:, ..) = spawn
  let instances = {
    use <- bool.guard(!is_despawn_on_reset, instances)
    list.each(instances, despawn_instance)
    []
  }

  use <- bool.guard(min_spawns < 1, SpawnMobile(..spawn, instances: instances))
  // for 1..min_spawns, get spawn_location and spawn an instance
  let room_ids = spawn.room_ids
  case spawn.strategy {
    Random -> {
      // spawn minimum count at random locations sampled from room list
      let instances = {
        list.range(1, min_spawns)
        |> list.map(fn(_) { lib.random(room_ids) })
        |> list.filter_map(fn(room_id) { spawn_instance(spawn, room_id) })
        |> list.append(instances)
      }
      SpawnMobile(..spawn, instances: instances)
    }

    RoundRobin -> {
      // spawn minimum count but select room_ids round robin style from the list
      let #(round_robin_tail, room_id_results) =
        list.range(1, min_spawns)
        |> list.map_fold(spawn.round_robin_tail, fn(tail, _) {
          spawn_location_round_robin(tail, room_ids)
        })

      let instances =
        room_id_results
        |> list.filter_map(identity)
        |> list.filter_map(fn(room_id) { spawn_instance(spawn, room_id) })
        |> list.append(instances)

      SpawnMobile(
        ..spawn,
        instances: instances,
        round_robin_tail: round_robin_tail,
      )
    }
  }
}

fn spawn_location_round_robin(
  round_robin_tail: List(Id(Room)),
  room_ids: List(Id(Room)),
) -> #(List(Id(Room)), Result(Id(Room), Nil)) {
  // cycle the room_id list where the tail is the remainder of the room_id list
  case round_robin_tail, room_ids {
    [first, ..rest], _ -> #(rest, Ok(first))
    [], [first, ..rest] -> #(rest, Ok(first))
    _, [] -> #(round_robin_tail, Error(Nil))
  }
}

fn spawn_instance(
  spawn: Spawn,
  room_id: Id(Room),
) -> Result(SpawnInstance, pog.QueryError) {
  case spawn {
    SpawnMobile(template_id:, ..) -> spawn_mob_instance(template_id, room_id)
    _ -> todo
  }
}

fn spawn_mob_instance(
  template_id: Id(MobTemplate),
  room_id: Id(Room),
) -> Result(SpawnInstance, pog.QueryError) {
  case todo {
    Ok(pog.Returned(rows: [mob_instance_id], ..)) -> todo
    Ok(_) -> todo
    error -> todo
  }
}

fn despawn_instance(instances: SpawnInstance) -> Nil {
  todo
}
