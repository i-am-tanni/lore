//// Route the event to the handler given the received event data.
////

import gleam/bool
import gleam/dict.{type Dict}
import gleam/list
import gleam/result.{try}
import lore/character/act
import lore/character/conn.{type Conn}
import lore/character/flag
import lore/character/view
import lore/character/view/character_view
import lore/character/view/combat_view
import lore/character/view/communication_view
import lore/character/view/door_view
import lore/character/view/error_view
import lore/character/view/item_view
import lore/character/view/move_view
import lore/world.{type Id, type Room}
import lore/world/event.{type CharacterEvent, type Event, type RoomMessage}
import lore/world/items
import lore/world/system_tables

pub fn route_player(
  conn: Conn,
  event: Event(CharacterEvent, RoomMessage),
) -> Conn {
  case event.data {
    event.ActFailed(reason) ->
      conn
      |> conn.renderln(error_view.room_request_error(reason))
      |> conn.prompt()
    // move events
    //
    event.MoveNotifyArrive(data) -> notify_arrive(conn, event, data)
    event.MoveNotifyDepart(data) -> notify_depart(conn, event, data)
    event.MoveCommit(data) -> move_commit(conn, event, data)
    event.DoorNotify(data) -> notify(conn, event, data, door_view.notify)
    // communication
    //
    event.Communication(data) ->
      notify(conn, event, data, communication_view.notify)
    // item events
    //
    event.ItemGetNotify(item) -> item_get(conn, event, item)
    event.ItemDropNotify(item) -> item_drop(conn, event, item)
    event.ItemInspect(item) -> item_look_at(conn, item)
    // combat
    //
    event.CombatCommit(data) -> combat_commit(conn, data)
    event.CombatRound(participants:, commits:) ->
      combat_commit_round(conn, participants, commits)
    event.CombatRoundPoll -> combat_round_poll(conn)
    // requests to expose internal data
    //
    event.MobileInspectRequest(by: requester) ->
      conn.character_event(
        conn,
        event.MobileInspectResponse(conn.character_get(conn)),
        send: requester,
      )

    event.MobileInspectResponse(character:) ->
      conn
      |> conn.renderln(character_view.look_at(character))
      |> conn.prompt()

    event.Kick(initiated_by: admin) ->
      conn
      |> conn.renderln(
        ["You have been kicked by ", admin, "!"]
        |> view.Leaves,
      )
      |> conn.terminate()

    event.Teleport(room_id:) -> conn.event(conn, event.TeleportRequest(room_id))
  }
}

fn notify(
  conn: Conn,
  event: Event(CharacterEvent, a),
  data: data,
  render_fun: fn(world.MobileInternal, world.Mobile, data) -> view.View,
) -> Conn {
  let view = render_fun(conn.character_get(conn), event.acting_character, data)
  conn
  |> conn.renderln(view)
  |> conn.prompt()
}

//
// Movement
//

fn move_commit(
  conn: Conn,
  _event: Event(CharacterEvent, RoomMessage),
  to_room_id: Id(Room),
) -> Conn {
  // The zone communicates to the character that the move is official,
  // so the first thing they do is update their room id to the destination room.
  //
  let character = conn.character_get(conn)
  let update = world.MobileInternal(..character, room_id: to_room_id)

  conn
  |> conn.character_put(update)
}

fn notify_arrive(
  conn: Conn,
  event: Event(CharacterEvent, RoomMessage),
  data: event.NotifyArriveData,
) -> Conn {
  let self = conn.character_get(conn)
  // Discard if acting_character
  use <- bool.guard(event.is_from_acting_character(event, self), conn)
  let event.NotifyArriveData(enter_keyword:, ..) = data
  conn.renderln(
    conn,
    move_view.notify_arrive(event.acting_character, enter_keyword),
  )
  |> conn.prompt()
}

fn notify_depart(
  conn: Conn,
  event: Event(CharacterEvent, RoomMessage),
  data: event.NotifyDepartData,
) -> Conn {
  let event.NotifyDepartData(exit_keyword:, ..) = data
  conn
  |> conn.renderln(move_view.notify_depart(event.acting_character, exit_keyword))
  |> conn.prompt()
}

//
// Items
//

fn item_get(
  conn: Conn,
  event: Event(CharacterEvent, RoomMessage),
  item_instance: world.ItemInstance,
) -> Conn {
  let result = {
    use item <- result.try(item_load(conn, item_instance))
    let self = conn.character_get(conn)
    case event.is_from_acting_character(event, self) {
      True -> {
        let update = [item_instance, ..self.inventory]

        conn
        |> conn.character_put(world.MobileInternal(..self, inventory: update))
        |> conn.renderln(item_view.get(self, event.acting_character, item))
        |> Ok
      }

      False ->
        conn.renderln(conn, item_view.get(self, event.acting_character, item))
        |> Ok
    }
  }

  case result {
    Ok(update) -> conn.prompt(update)
    Error(Nil) -> conn
  }
}

fn item_drop(
  conn: Conn,
  event: Event(CharacterEvent, RoomMessage),
  item_instance: world.ItemInstance,
) -> Conn {
  let result = {
    use item <- result.try(item_load(conn, item_instance))
    let self = conn.character_get(conn)
    case event.is_from_acting_character(event, self) {
      True -> {
        let update =
          list.filter(self.inventory, fn(x) { item_instance.id != x.id })

        conn
        |> conn.character_put(world.MobileInternal(..self, inventory: update))
        |> conn.renderln(item_view.drop(self, event.acting_character, item))
        |> Ok
      }

      False ->
        conn.renderln(conn, item_view.drop(self, event.acting_character, item))
        |> Ok
    }
  }

  case result {
    Ok(update) -> conn.prompt(update)
    Error(Nil) -> conn
  }
}

pub fn item_look_at(conn: Conn, item_instance: world.ItemInstance) -> Conn {
  case item_load(conn, item_instance), item_instance.contains {
    Ok(item), world.NotContainer ->
      conn
      |> conn.renderln(item_view.inspect(item))
      |> conn.prompt

    Ok(item), world.Contains(contents) -> {
      let system_tables.Lookup(items:, ..) = conn.system_tables(conn)

      conn
      |> conn.renderln(item_view.inspect(item))
      |> conn.renderln(item_view.item_contains(items, contents))
      |> conn.prompt
    }

    Error(Nil), _ -> conn
  }
}

fn item_load(
  conn: Conn,
  item_instance: world.ItemInstance,
) -> Result(world.Item, Nil) {
  let system_tables.Lookup(items:, ..) = conn.system_tables(conn)
  case item_instance.item {
    world.Loading(id) -> items.load(items, id)
    world.Loaded(item) -> Ok(item)
  }
}

//
// Combat
//

fn combat_commit(conn: Conn, data: event.CombatCommitData) -> Conn {
  let self = conn.character_get(conn)
  let event.CombatCommitData(attacker:, victim:, ..) = data
  let victim_id = victim.id
  let is_victim_dead = victim.hp <= 0
  let has_auto_revive = flag.affect_has(self.affects.flags, flag.AutoRevive)
  let conn = case self.id {
    self_id if self_id == victim_id && is_victim_dead && !has_auto_revive ->
      conn.terminate(conn)

    self_id if self_id == victim_id ->
      sync_mobile(victim, self)
      |> conn.character_put(conn, _)

    self_id if self_id == attacker.id ->
      sync_mobile(attacker, self)
      |> conn.character_put(conn, _)

    _ -> conn
  }

  case is_victim_dead {
    True -> conn.renderln(conn, combat_view.notify(self, data)) |> conn.prompt()
    False -> conn.render(conn, combat_view.notify(self, data))
  }
}

fn combat_round_poll(conn: Conn) -> Conn {
  let self = conn.character_get(conn)
  case self.fighting {
    world.Fighting(victim_id) -> auto_attack(conn, victim_id)
    _ -> conn
  }
}

fn combat_commit_round(
  conn: Conn,
  participants: Dict(world.StringId(world.Mobile), world.Mobile),
  commits: List(event.CombatPollData),
) -> Conn {
  let result = {
    let self = conn.character_get(conn)
    use self <- try(
      dict.get(participants, self.id)
      |> result.map(sync_mobile(_, self)),
    )

    let has_auto_revive = flag.affect_has(self.affects.flags, flag.AutoRevive)
    let conn =
      conn
      |> conn.character_put(self)
      |> conn.renderln(combat_view.round_report(self, participants, commits))

    case self.fighting {
      _ if self.hp <= 0 && !has_auto_revive -> conn.terminate(conn)

      world.Fighting(victim_id) ->
        conn
        |> auto_attack(victim_id)
        |> conn.renderln(combat_view.round_summary(self, participants))
        |> conn.prompt

      world.NoTarget -> conn.prompt(conn)
    }
    |> Ok
  }

  case result {
    Ok(update) -> update
    _ -> conn
  }
}

fn auto_attack(conn: Conn, victim_id: world.StringId(world.Mobile)) -> Conn {
  event.CombatRequestData(
    victim: event.SearchId(victim_id),
    dam_roll: world.random(8),
    is_round_based: True,
  )
  |> act.kill
  |> conn.action(conn, _)
}

fn sync_mobile(
  update: world.Mobile,
  self: world.MobileInternal,
) -> world.MobileInternal {
  case update.hp <= 0 && flag.affect_has(self.affects.flags, flag.AutoRevive) {
    True -> world.MobileInternal(..self, hp: self.hp_max)

    _ -> {
      let world.Mobile(hp:, fighting:, ..) = update
      world.MobileInternal(..self, hp:, fighting:)
    }
  }
}
