import gleam/bool
import gleam/list
import gleam/otp/actor
import gleam/pair
import gleam/result.{try}
import lore/character/character_registry
import lore/character/pronoun
import lore/world.{
  type Id, type Mobile, type Npc, type Room, type SpawnGroup, Id, MobSpawn,
  SpawnGroup,
}
import lore/world/event
import lore/world/mob_factory
import lore/world/sql
import lore/world/system_tables
import pog

type SpawnError(a) {
  Database(pog.QueryError)
  NotStarted(actor.StartError)
  IdNotFound(Int)
}

pub fn reset_group(
  group: SpawnGroup,
  system_tables: system_tables.Lookup,
) -> SpawnGroup {
  use <- bool.guard(!group.is_enabled, group)
  case group.is_despawn_on_reset {
    True -> reset_with_despawn(group, system_tables)
    False -> reset(group, system_tables)
  }
}

fn reset(group: SpawnGroup, system_tables: system_tables.Lookup) -> SpawnGroup {
  let registry = system_tables.character
  let SpawnGroup(instances:, members:, ..) = group

  let active_instances =
    list.filter_map(instances, fn(instance) {
      let #(_, instance_id) = instance
      use _ <- try(character_registry.whereis(registry, instance_id))
      Ok(instance)
    })

  let active_spawn_ids = list.map(active_instances, pair.first)

  let instances =
    // filter for inactive spawns
    list.filter(members, fn(member) {
      !list.contains(active_spawn_ids, member.spawn_id)
    })
    // then spawn inactives
    |> list.filter_map(fn(spawn) {
      let MobSpawn(spawn_id:, mobile_id:, room_id:) = spawn
      let db = pog.named_connection(system_tables.db)
      use mobile <- try(generate_mobile(db, mobile_id, in: room_id))
      use _ <- try(
        mob_factory.start_child(system_tables.mob_factory, mobile)
        |> result.map_error(NotStarted),
      )
      Ok(#(spawn_id, mobile.id))
    })
    |> list.append(active_instances)

  SpawnGroup(..group, instances:)
}

fn reset_with_despawn(
  group: SpawnGroup,
  system_tables: system_tables.Lookup,
) -> SpawnGroup {
  let registry = system_tables.character
  let SpawnGroup(instances:, members:, ..) = group

  // despawn instances
  list.each(instances, fn(instance) {
    let #(_, instance_id) = instance
    use subject <- try(character_registry.whereis(registry, instance_id))
    Ok(actor.send(subject, event.ServerRequestedShutdown))
  })

  let instances =
    list.filter_map(members, fn(spawn) {
      let MobSpawn(spawn_id:, mobile_id:, room_id:) = spawn
      let db = pog.named_connection(system_tables.db)
      use mobile <- try(generate_mobile(db, mobile_id, in: room_id))
      use _ <- try(
        mob_factory.start_child(system_tables.mob_factory, mobile)
        |> result.map_error(NotStarted),
      )
      Ok(#(spawn_id, mobile.id))
    })

  SpawnGroup(..group, instances:)
}

fn generate_mobile(
  db: pog.Connection,
  mobile_id: Id(Npc),
  in room_id: Id(Room),
) -> Result(world.MobileInternal, SpawnError(Mobile)) {
  let world.Id(mobile_id) = mobile_id
  use returned <- try(
    sql.mobile_by_id(db, mobile_id)
    |> result.map_error(Database),
  )
  case returned {
    pog.Returned(count: 1, rows: [data]) -> Ok(to_mobile(data, room_id))
    _ -> Error(IdNotFound(mobile_id))
  }
}

fn to_mobile(row: sql.MobileByIdRow, room_id: Id(Room)) -> world.MobileInternal {
  world.MobileInternal(
    id: world.generate_id(),
    room_id:,
    template_id: world.Npc(Id(row.mobile_id)),
    name: row.name,
    keywords: row.keywords,
    pronouns: pronoun.Masculine,
    short: row.short,
    inventory: [],
  )
}
