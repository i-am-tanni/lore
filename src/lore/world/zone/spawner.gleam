//// SpawnGroups are essentially encounters that can reset on a timer.
////

import gleam/bool
import gleam/list
import gleam/otp/actor
import gleam/pair
import gleam/result.{try}
import gleam/set
import lore/character/character_registry
import lore/character/pronoun
import lore/character/users
import lore/world.{
  type Id, type Mobile, type Npc, type Room, type SpawnGroup, Id, MobSpawn,
  SpawnGroup,
}
import lore/world/event
import lore/world/items
import lore/world/mob_factory
import lore/world/room/presence
import lore/world/room/room_registry
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
    True ->
      group
      |> reset_mobs_with_despawn(system_tables)
      |> reset_items(system_tables)

    False ->
      group
      |> reset_mobs(system_tables)
      |> reset_items(system_tables)
  }
}

pub fn reset_items(
  group: SpawnGroup,
  system_tables: system_tables.Lookup,
) -> SpawnGroup {
  let item_instances =
    list.filter_map(group.item_members, fn(member) {
      use item <- try(generate_item(member.item_id, system_tables))
      use room_subject <- try(room_registry.whereis(
        system_tables.room,
        member.room_id,
      ))
      actor.send(room_subject, event.SpawnItem(item))
      #(member.spawn_id, item.id)
      |> Ok
    })

  SpawnGroup(..group, item_instances:)
}

fn reset_mobs(
  group: SpawnGroup,
  system_tables: system_tables.Lookup,
) -> SpawnGroup {
  let registry = system_tables.character
  let SpawnGroup(mob_instances:, mob_members:, ..) = group

  let active_instances =
    list.filter_map(mob_instances, fn(instance) {
      let #(_, instance_id) = instance
      use _ <- try(character_registry.whereis(registry, instance_id))
      Ok(instance)
    })

  let active_spawn_ids = list.map(active_instances, pair.first)

  let mob_instances =
    mob_members
    |> reject_spawn_ids(active_spawn_ids)
    |> spawn_mobs(system_tables)
    |> list.append(active_instances)

  SpawnGroup(..group, mob_instances:)
}

fn reset_mobs_with_despawn(
  group: SpawnGroup,
  system_tables: system_tables.Lookup,
) -> SpawnGroup {
  let character_registry = system_tables.character
  let presence = system_tables.presence
  let SpawnGroup(mob_instances:, mob_members:, ..) = group

  // Instance must be in a room depopulated of players to despawn
  let rooms_occupied_by_player = {
    users.players_logged_in(system_tables.users)
    |> list.filter_map(fn(user) {
      use room_id <- try(presence.lookup(presence, user.id))
      Ok(room_id)
    })
    |> set.from_list
  }

  let #(cannot_despawn, can_despawn) =
    list.partition(mob_instances, fn(instance) {
      let #(_, instance_id) = instance
      case presence.lookup(presence, instance_id) {
        Ok(room_id) -> set.contains(rooms_occupied_by_player, room_id)
        Error(Nil) -> False
      }
    })

  // despawn instances
  list.each(can_despawn, fn(instance) {
    let #(_, instance_id) = instance
    use subject <- try(character_registry.whereis(
      character_registry,
      instance_id,
    ))
    Ok(actor.send(subject, event.ServerRequestedShutdown))
  })

  let cannot_despawn_ids = list.map(cannot_despawn, pair.first)

  let mob_instances =
    mob_members
    |> reject_spawn_ids(cannot_despawn_ids)
    |> spawn_mobs(system_tables)
    |> list.append(cannot_despawn)

  SpawnGroup(..group, mob_instances:)
}

fn spawn_mobs(
  to_spawn: List(world.MobSpawn),
  system_tables: system_tables.Lookup,
) -> List(#(Id(world.MobSpawn), world.StringId(Mobile))) {
  let db = pog.named_connection(system_tables.db)
  let mob_factory = system_tables.mob_factory

  list.filter_map(to_spawn, fn(spawn) {
    let MobSpawn(spawn_id:, mobile_id:, room_id:) = spawn
    use mobile <- try(generate_mobile(db, mobile_id, in: room_id))
    use _ <- try(
      mob_factory.start_child(mob_factory, mobile)
      |> result.map_error(NotStarted),
    )
    Ok(#(spawn_id, mobile.id))
  })
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

fn generate_item(
  item_id: Id(world.Item),
  system_tables: system_tables.Lookup,
) -> Result(world.ItemInstance, Nil) {
  use item <- try(items.load(system_tables.items, item_id))
  world.ItemInstance(
    id: world.generate_id(),
    item: world.Loading(item_id),
    keywords: item.keywords,
  )
  |> Ok()
}

// reject any members of list
fn reject_spawn_ids(
  spawns: List(world.MobSpawn),
  rejects: List(Id(world.MobSpawn)),
) -> List(world.MobSpawn) {
  case rejects != [] {
    True ->
      list.filter(spawns, fn(spawn) { !list.contains(rejects, spawn.spawn_id) })

    False -> spawns
  }
}
