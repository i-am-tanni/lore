/// An actor for a room process, which serves as a synchronization point
/// for physical actions and tracks the room state.
///
import gleam/bool
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/otp/actor
import gleam/result.{try}
import gleam/set
import gleam/time/duration
import gleam/time/timestamp
import lore/character/flag
import lore/character/view
import lore/character/view/render
import lore/server/my_list
import lore/world.{
  type ErrorRoomRequest, type Id, type Mobile, type Room, type StringId, Closed,
  Open,
}
import lore/world/event.{
  type CharacterMessage, type CharacterToRoomEvent, type Event, type RoomMessage,
}
import lore/world/room/effect.{type RoomEffect}
import lore/world/room/janitor
import lore/world/room/presence
import lore/world/room/room_registry
import lore/world/system_tables

const combat_round_len_in_ms = 3000

type Timer {
  Timer(timer: process.Timer, fire_at: timestamp.Timestamp)
  Cancelled
}

type Found {
  Item(world.ItemInstance)
  Mobile(world.Mobile)
  ExtraDesc(world.ExtraDesc)
}

type State {
  State(
    room: world.Room,
    system_tables: system_tables.Lookup,
    self: process.Subject(RoomMessage),
    combat_queue: List(event.CombatPollData),
    combat_timer: Timer,
    is_in_combat: Bool,
  )
}

pub type Model {
  Model(
    room: world.Room,
    lookup: system_tables.Lookup,
    is_in_combat: Bool,
    combat_queue: List(event.CombatPollData),
  )
}

/// Starts a room and registers it.
///
pub fn start(
  room: Room,
  system_tables: system_tables.Lookup,
) -> Result(actor.Started(process.Subject(RoomMessage)), actor.StartError) {
  actor.new_with_initialiser(100, fn(self) { init(self, room, system_tables) })
  |> actor.on_message(recv)
  |> actor.start
}

fn init(
  self: process.Subject(RoomMessage),
  room: Room,
  system_tables: system_tables.Lookup,
) -> Result(actor.Initialised(State, RoomMessage, Subject(RoomMessage)), String) {
  // register room on init
  room_registry.register(system_tables.room, room.id, self)

  let update =
    list.map(room.items, fn(instance) {
      world.ItemInstance(..instance, id: world.generate_id())
    })
  let room = world.Room(..room, items: update)

  State(
    room:,
    system_tables:,
    self:,
    combat_queue: [],
    combat_timer: Cancelled,
    is_in_combat: False,
  )
  |> actor.initialised()
  |> actor.selecting(process.new_selector() |> process.select(self))
  |> actor.returning(self)
  |> Ok
}

fn recv(state: State, msg: RoomMessage) -> actor.Next(State, RoomMessage) {
  let state = case msg {
    event.CharacterToRoom(event) -> route_from_character(state, event)
    event.PollRoom(event) -> poll_room(state, event)
    event.InterRoom(event) -> route_from_zone(state, event)
    event.MobileCleanup(mobile_id) -> {
      // clean up dead or crashed mobile
      let world.Room(characters:, ..) as room = state.room
      let characters =
        list.filter(characters, fn(character) { mobile_id != character.id })
      let update = world.Room(..room, characters:)
      State(..state, room: update)
    }

    event.SpawnItem(item_instance) -> {
      let world.Room(items:, ..) as room = state.room
      case is_item_present(items, item_instance) {
        True -> state
        False ->
          State(
            ..state,
            room: world.Room(..room, items: [item_instance, ..items]),
          )
      }
    }

    event.DespawnItems(item_ids) -> {
      let world.Room(items:, ..) as room = state.room
      let filtered =
        list.filter(items, fn(item) {
          let item_id = item.id
          !list.any(item_ids, fn(id) { id == item_id })
        })

      let room = world.Room(..room, items: filtered)
      State(..state, room:)
    }

    event.RoomToRoom(..) -> state
    event.CombatRoundTrigger -> {
      let combat_queue = state.combat_queue
      let state = State(..state, combat_timer: Cancelled, combat_queue: [])
      let model = to_model(state)
      let #(model, effect) = combat_round_trigger(model, combat_queue)
      effect.realize(
        effect,
        from: state.self,
        by: world.mobile_identity(),
        in: state.room,
        with_context: state.system_tables,
      )

      update(state, model)
    }
  }

  actor.continue(state)
}

fn route_from_character(
  state: State,
  event: Event(event.CharacterToRoomEvent, event.CharacterMessage),
) -> State {
  let model = to_model(state)
  let #(model, effect) = case event.data {
    event.MoveRequest(data) -> move_request(model, event, data)
    event.TeleportRequest(data) -> teleport_request(model, event, data)
    event.MoveArrive(data) -> move_arrive(model, event, data)
    event.Look -> look_room(model, event)
    event.LookAt(data) -> look_at(model, event, data)
    event.RejoinRoom -> rejoin_room(model, event)
    event.DoorToggle(data) -> door_request(model, event, data)
    event.DoorUpdateEnd(data) -> door_update(model, event, data)
    event.RoomCommunication(data) -> broadcast(model, event, data)
    event.ItemGet(data) -> item_get(model, event, data)
    event.ItemDrop(data) -> item_drop(model, event, data)
    event.CombatRequest(data) -> combat_request(model, event, data)
    event.Slay(data) -> combat_slay(model, event, data)
    event.UpdateCharacter ->
      update_character_in_room(model, event, event.acting_character)
  }

  effect.realize(
    effect,
    from: state.self,
    by: event.acting_character,
    in: state.room,
    with_context: state.system_tables,
  )

  update(state, model)
}

fn route_from_zone(
  state: State,
  event: Event(event.InterRoomEvent, event.Done),
) -> State {
  let model = to_model(state)

  let #(model, effect) = case event.data {
    event.MoveDepart(data) -> move_depart(model, event, data)
    event.DoorUpdateBegin(data) -> {
      let #(model, effect) = door_update(model, event, data)
      #(model, effect.batch([effect.send(event.from, event.Done), effect]))
    }
  }

  effect.realize(
    effect,
    from: state.self,
    by: event.acting_character,
    in: state.room,
    with_context: state.system_tables,
  )

  update(state, model)
}

fn poll_room(
  state: State,
  event: Event(event.PollEvent, world.Vote(world.ErrorRoomRequest)),
) -> State {
  let model = to_model(state)

  let #(model, effect) = case event.data {
    event.MovePoll(data) -> move_vote(model, event, data)
  }

  effect.realize(
    effect,
    from: state.self,
    by: event.acting_character,
    in: state.room,
    with_context: state.system_tables,
  )

  update(state, model)
}

fn to_model(state: State) -> Model {
  Model(
    room: state.room,
    lookup: state.system_tables,
    combat_queue: state.combat_queue,
    is_in_combat: state.is_in_combat,
  )
}

fn update(state: State, model: Model) -> State {
  let is_in_combat = model.is_in_combat
  let combat_timer = case state.combat_timer {
    Cancelled if is_in_combat ->
      schedule_combat_round(state.self, combat_round_len_in_ms)

    Timer(timer:, ..) if !is_in_combat -> {
      process.cancel_timer(timer)
      Cancelled
    }

    no_change -> no_change
  }

  State(
    ..state,
    room: model.room,
    system_tables: model.lookup,
    combat_queue: model.combat_queue,
    is_in_combat: model.is_in_combat,
    combat_timer:,
  )
}

fn schedule_combat_round(
  self: process.Subject(RoomMessage),
  combat_round_len_in_ms: Int,
) -> Timer {
  let now = timestamp.system_time()
  let delay =
    now
    |> timestamp.to_unix_seconds
    // convert to ms
    |> float.multiply(1000.0)
    |> float.truncate
    |> int.modulo(combat_round_len_in_ms)
    |> result.unwrap(0)
    |> int.subtract(combat_round_len_in_ms, _)

  Timer(
    timer: process.send_after(self, delay, event.CombatRoundTrigger),
    fire_at: timestamp.add(now, duration.milliseconds(delay)),
  )
}

type CombatRoundTemp {
  CombatRoundTemp(
    participants: Dict(StringId(world.Mobile), world.Mobile),
    commits: List(event.CombatPollData),
    continue: Bool,
  )
}

//
// Room event handling
// Will return state and effects separately
//

//
// Movement
//

/// The initial movement request by a character via an exit keyword.
///
fn move_request(
  model: Model,
  event: Event(CharacterToRoomEvent, CharacterMessage),
  exit_keyword: world.Direction,
) -> #(Model, RoomEffect(CharacterMessage)) {
  let result = {
    // If exit exists, confirm room subject and send to the zone.
    // This cannot fail as only characters can initiate move events
    let acting_character = event.acting_character
    use exit_match <- try(find_local_exit(model.room.exits, exit_keyword))
    use _ <- try(can_access(exit_match))
    let world.RoomExit(from_room_id:, to_room_id:, ..) = exit_match

    event.MoveKickoffData(
      from: event.from,
      acting_character:,
      from_room_id:,
      to_room_id:,
      exit_keyword: Some(exit_keyword),
    )
    |> event.MoveKickoff
    |> Ok
  }

  let effect = case result {
    Ok(move_proceed) -> effect.send_zone(move_proceed)
    Error(reason) -> effect.send_character(event.from, event.ActFailed(reason))
  }

  #(model, effect)
}

/// The initial movement request by a character for an exit keyword.
///
fn teleport_request(
  model: Model,
  event: Event(CharacterToRoomEvent, CharacterMessage),
  to_room_id: Id(world.Room),
) -> #(Model, RoomEffect(CharacterMessage)) {
  let result = {
    // If exit exists, proceed, lookup room subject, and send to zone
    // This cannot fail as only characters can initiate move events
    let acting_character = event.acting_character

    event.MoveKickoffData(
      from: event.from,
      acting_character:,
      from_room_id: model.room.id,
      to_room_id:,
      exit_keyword: None,
    )
    |> event.MoveKickoff
    |> Ok
  }

  let effect = case result {
    Ok(move_proceed) -> effect.send_zone(move_proceed)
    Error(reason) -> effect.send_character(event.from, event.ActFailed(reason))
  }

  #(model, effect)
}

/// Destination room votes whether to accept the character's move.
///
fn move_vote(
  model: Model,
  event: Event(event.PollEvent, world.Vote(ErrorRoomRequest)),
  _data: world.Mobile,
) -> #(Model, RoomEffect(world.Vote(ErrorRoomRequest))) {
  #(model, effect.send(event.from, world.Approve))
}

/// Remove departing character from room and notify occupants.
///
fn move_depart(
  model: Model,
  event: Event(event.InterRoomEvent, event.Done),
  data: event.MoveDepartData,
) -> #(Model, RoomEffect(event.Done)) {
  let acting_character = event.acting_character
  let event.MoveDepartData(exit_keyword:, subject:) = data
  let notification =
    event.NotifyDepartData(exit_keyword:, acting_character:)
    |> event.MoveNotifyDepart

  let model = {
    let to_remove_id = event.acting_character.id
    let room = model.room
    let filtered =
      list.filter(room.characters, fn(character) {
        character.id != to_remove_id
      })
    let room = world.Room(..room, characters: filtered)
    Model(..model, room:)
  }

  let effects = [
    effect.room_unsubscribe(subject),
    effect.broadcast(notification),
    effect.send(event.from, event.Done),
  ]

  #(model, effect.batch(effects))
}

fn move_arrive(
  model: Model,
  event: Event(event.CharacterToRoomEvent, CharacterMessage),
  data: event.MoveArriveData,
) -> #(Model, RoomEffect(CharacterMessage)) {
  let acting_character = event.acting_character
  let event.MoveArriveData(from_room_id, from_exit_keyword) = data

  // Check to see if there is a direction we can infer from the arrival
  let room_exit = case from_room_id {
    Some(id) ->
      list.find(model.room.exits, fn(room_exit) { room_exit.to_room_id == id })
      |> option.from_result

    None -> None
  }

  let enter_keyword = case room_exit {
    Some(world.RoomExit(keyword:, ..)) -> Some(keyword)
    None -> None
  }

  // We will send occupants an arrival notification
  let notification =
    event.NotifyArriveData(enter_keyword:, acting_character:)
    |> event.MoveNotifyArrive

  let room = model.room
  let model = {
    let room =
      world.Room(..room, characters: [acting_character, ..room.characters])
    Model(..model, room:)
  }

  let optional_effect = case is_player(event.acting_character) {
    True -> {
      fn() {
        [
          render.exit(from_exit_keyword),
          render.room_with_mini_map_impure(
            room,
            event.acting_character,
            model.lookup,
          ),
        ]
        |> view.join("\n")
      }
      |> effect.render_lazy(event.from, _)
      |> list.wrap
    }

    False -> []
  }

  let effects = [
    effect.lazy(fn() {
      presence.update(
        model.lookup.presence,
        event.from,
        acting_character.id,
        room.id,
      )
    }),
    effect.broadcast(notification),
    effect.room_subscribe(event.from),
    ..optional_effect
  ]

  #(model, effect.Batch(effects))
}

fn look_room(
  model: Model,
  event: Event(event.CharacterToRoomEvent, CharacterMessage),
) -> #(Model, RoomEffect(CharacterMessage)) {
  let effect =
    effect.render_lazy(event.from, fn() {
      render.room_with_mini_map_impure(
        model.room,
        event.acting_character,
        model.lookup,
      )
    })

  #(model, effect)
}

fn look_at(
  model: Model,
  event: Event(event.CharacterToRoomEvent, CharacterMessage),
  search_term: String,
) -> #(Model, RoomEffect(CharacterMessage)) {
  let room = model.room

  let result = {
    use <- result.lazy_or(
      find_local_item(room.items, search_term)
      |> result.map(Item),
    )
    use <- result.lazy_or(
      find_local_character(room.characters, event.Keyword(search_term))
      |> result.map(Mobile)
      |> result.replace_error(Nil),
    )
    find_local_xdesc(room.xdescs, search_term)
    |> result.map(ExtraDesc)
  }

  let effect = case result {
    Ok(Item(item_match)) ->
      effect.send_character(event.from, event.ItemInspect(item_match))
    Ok(Mobile(world.Mobile(id:, ..))) ->
      effect.send_character_id(id, event.MobileInspectRequest(event.from))
    Ok(ExtraDesc(xdesc_match)) ->
      effect.renderln(event.from, view.text(xdesc_match.text))
    Error(_) ->
      effect.send_character(
        event.from,
        event.ActFailed(world.NotFound(search_term)),
      )
  }

  #(model, effect)
}

fn update_character_in_room(
  model: Model,
  _event: Event(event.CharacterToRoomEvent, CharacterMessage),
  acting_character: world.Mobile,
) -> #(Model, RoomEffect(CharacterMessage)) {
  let update = {
    let room = model.room
    let characters =
      my_list.update(room.characters, update_character(
        _,
        acting_character.id,
        acting_character,
      ))
    let room = world.Room(..room, characters:)
    Model(..model, room:)
  }

  #(update, effect.EffectNone)
}

/// Only called if character restarted and needs to resubscribe to the room.
///
fn rejoin_room(
  model: Model,
  event: Event(event.CharacterToRoomEvent, CharacterMessage),
) -> #(Model, RoomEffect(CharacterMessage)) {
  // Check that requester is in the room they believe themselves to be in
  // before subscribing them
  let acting_character_id = event.acting_character.id
  let is_present =
    list.any(model.room.characters, fn(mobile) {
      mobile.id == acting_character_id
    })

  let effect = case is_present {
    True -> effect.room_subscribe(event.from)
    // Well this is awkward...
    False -> effect.EffectNone
  }

  #(model, effect)
}

//
// Local Communication
//

fn broadcast(
  model: Model,
  event: Event(event.CharacterToRoomEvent, CharacterMessage),
  data: event.RoomCommunicationData,
) -> #(Model, RoomEffect(CharacterMessage)) {
  let result = case data {
    event.SayData(text:, adverb:) -> Ok(event.Say(text:, adverb:))

    event.SayAtData(at:, text:, adverb:) -> {
      list.find(model.room.characters, character_keyword_matches(_, at))
      |> result.map(fn(victim) { event.SayAt(text:, adverb:, at: victim) })
    }

    event.WhisperData(at:, text:, ..) -> {
      list.find(model.room.characters, character_keyword_matches(_, at))
      |> result.map(fn(victim) { event.Whisper(text:, at: victim) })
    }

    event.EmoteData(text:) -> Ok(event.Emote(text:))

    event.SocialData(report:) -> Ok(event.Social(report:))

    event.SocialAtData(report:, at:) -> {
      list.find(model.room.characters, character_keyword_matches(_, at))
      |> result.map(fn(victim) { event.SocialAt(report:, at: victim) })
    }
  }

  let effect = case result {
    Ok(data) -> effect.broadcast(event.Communication(data))
    Error(_) ->
      event.ActFailed(world.CharacterLookupFailed)
      |> effect.send_character(event.from, _)
  }

  #(model, effect)
}

//
// Items
//

fn item_get(
  model: Model,
  event: Event(CharacterToRoomEvent, CharacterMessage),
  search_term: String,
) -> #(Model, RoomEffect(CharacterMessage)) {
  let result = {
    use world.ItemInstance(id:, ..) as item_instance <- try(
      list.find(model.room.items, item_keyword_matches(_, search_term)),
    )

    let update = {
      let room = model.room
      let filtered = list.filter(room.items, fn(item) { item.id != id })
      let room = world.Room(..room, items: filtered)
      Model(..model, room:)
    }

    let effect = case item_instance.was_touched {
      True ->
        [
          // If item instance was previously touched by a mobile
          // then it was dropped and thus scheduled for clean up. Cancel that.
          effect.lazy(fn() {
            janitor.item_cancel_clean_up(model.lookup.janitor, item_instance.id)
          }),
          effect.broadcast(event.ItemGetNotify(item_instance)),
        ]
        |> effect.batch

      False -> {
        let item_instance =
          world.ItemInstance(..item_instance, was_touched: True)
        effect.broadcast(event.ItemGetNotify(item_instance))
      }
    }

    Ok(#(update, effect))
  }

  case result {
    Ok(update) -> update

    Error(_) -> {
      let effect =
        event.ActFailed(world.ItemLookupFailed(search_term))
        |> effect.send_character(event.from, _)

      #(model, effect)
    }
  }
}

fn item_drop(
  model: Model,
  _event: Event(CharacterToRoomEvent, CharacterMessage),
  item_instance: world.ItemInstance,
) -> #(Model, RoomEffect(CharacterMessage)) {
  let room = model.room
  let update = {
    let room = world.Room(..room, items: [item_instance, ..room.items])
    Model(..model, room:)
  }

  let effects = [
    effect.lazy(fn() {
      janitor.item_schedule_clean_up(
        model.lookup.janitor,
        what: item_instance.id,
        at: room.id,
        in: duration.minutes(5),
      )
    }),
    effect.broadcast(event.ItemDropNotify(item_instance)),
  ]

  #(update, effect.batch(effects))
}

//
// Doors
//

fn door_request(
  model: Model,
  event: Event(CharacterToRoomEvent, CharacterMessage),
  data: event.DoorToggleData,
) -> #(Model, RoomEffect(CharacterMessage)) {
  let event.DoorToggleData(exit_keyword:, desired_state:) = data
  let room = model.room
  let result = {
    use exit <- try(find_local_exit(room.exits, exit_keyword))
    use door <- try(
      exit.door
      |> option.to_result(world.DoorErr(world.MissingDoor(exit.keyword))),
    )
    // Is requested update valid?
    use door_id <- result.try(case door.state, desired_state {
      Open, Closed -> Ok(door.id)
      Closed, Open -> Ok(door.id)
      Open, Open -> Error(world.DoorErr(world.NoChangeNeeded(Open)))
      Closed, Closed -> Error(world.DoorErr(world.NoChangeNeeded(Closed)))
    })

    event.DoorSyncData(
      door_id:,
      from: event.from,
      from_room_id: room.id,
      to_room_id: exit.to_room_id,
      update: desired_state,
    )
    |> event.DoorSync
    |> Ok
  }

  let effect = case result {
    Ok(door_sync) -> effect.send_zone(door_sync)
    Error(reason) -> effect.send_character(event.from, event.ActFailed(reason))
  }

  #(model, effect)
}

fn door_update(
  model: Model,
  _event: Event(a, b),
  data: event.DoorUpdateData,
) -> #(Model, RoomEffect(b)) {
  let event.DoorUpdateData(door_id:, update:, from_room_id:) = data
  let room = model.room
  let is_subject_observable = from_room_id == room.id

  let #(effects, updated_exits) =
    list.map_fold(room.exits, list.new(), fn(acc, exit) {
      case exit.door {
        Some(door) if door.id == door_id -> {
          let door = world.Door(..door, state: update)
          let effect =
            event.DoorNotifyData(exit:, update:, is_subject_observable:)
            |> event.DoorNotify
            |> effect.broadcast

          let updated = world.RoomExit(..exit, door: Some(door))
          #([effect, ..acc], updated)
        }

        _no_update -> #(acc, exit)
      }
    })

  let update = {
    let room = world.Room(..room, exits: updated_exits)
    Model(..model, room:)
  }

  let effect = case effects != [] {
    True -> effect.batch(effects)
    False -> effect.EffectNone
  }

  #(update, effect)
}

//
// Combat
//

fn combat_request(
  model: Model,
  event: Event(CharacterToRoomEvent, CharacterMessage),
  data: event.CombatRequestData,
) -> #(Model, RoomEffect(CharacterMessage)) {
  let attacker = event.acting_character

  let result = {
    use victim <- try(find_local_character(model.room.characters, data.victim))
    use <- bool.guard(
      flag.affect_has(victim.affects, flag.GodMode),
      Error(world.GodMode),
    )
    use <- bool.guard(is_pvp(attacker, victim), Error(world.PvpForbidden))
    event.CombatPollData(
      attacker_id: event.acting_character.id,
      victim_id: victim.id,
      dam_roll: data.dam_roll,
    )
    |> Ok
  }

  let is_round_based = data.is_round_based

  case result {
    Ok(round_data) if is_round_based && !model.is_in_combat -> {
      let update =
        Model(
          ..model,
          combat_queue: [round_data, ..model.combat_queue],
          is_in_combat: True,
        )
      #(update, effect.broadcast(event.CombatRoundPoll))
    }

    Ok(round_data) if is_round_based -> {
      let update =
        Model(
          ..model,
          combat_queue: [round_data, ..model.combat_queue],
          is_in_combat: True,
        )

      #(update, effect.EffectNone)
    }

    Ok(combat_data) -> combat_process(model, combat_data)

    Error(reason) -> {
      let effect = effect.send_character(event.from, event.ActFailed(reason))
      #(model, effect)
    }
  }
}

fn combat_process(
  model: Model,
  data: event.CombatPollData,
) -> #(Model, RoomEffect(CharacterMessage)) {
  let result = {
    let event.CombatPollData(victim_id:, attacker_id:, dam_roll:) = data
    let characters = model.room.characters
    // Make sure actors are still in the room
    use attacker <- try(find_local_character(
      characters,
      event.SearchId(attacker_id),
    ))
    use victim <- try(find_local_character(
      characters,
      event.SearchId(victim_id),
    ))

    // update victim
    let #(victim, is_victim_alive) = case victim.hp - dam_roll {
      hp if hp > 0 && victim.fighting == world.NoTarget -> #(
        world.Mobile(..victim, hp:, fighting: world.Fighting(attacker.id)),
        True,
      )

      hp if hp > 0 -> #(world.Mobile(..victim, hp:), True)

      // ..else victim is dead
      hp -> #(world.Mobile(..victim, hp:, fighting: world.NoTarget), False)
    }

    // update attacker
    let attacker_update = case attacker.fighting {
      world.NoTarget if is_victim_alive ->
        Some(world.Mobile(..attacker, fighting: world.Fighting(victim.id)))

      world.Fighting(_) if !is_victim_alive ->
        Some(world.Mobile(..attacker, fighting: world.NoTarget))

      _ -> None
    }

    // update room
    let room = {
      let characters = case attacker_update {
        Some(attacker) ->
          my_list.update(characters, fn(character) {
            use <- result.lazy_or(update_character(
              character,
              attacker.id,
              attacker,
            ))
            update_character(character, victim.id, victim)
          })

        None ->
          my_list.update(characters, update_character(_, victim.id, victim))
      }

      world.Room(..model.room, characters:)
    }

    let attacker = option.unwrap(attacker_update, attacker)

    let combat_commit =
      event.CombatCommitData(victim:, attacker:, damage: dam_roll)
      |> event.CombatCommit
      |> effect.broadcast

    case is_victim_alive && !model.is_in_combat {
      True -> {
        let update = Model(..model, room:, is_in_combat: True)
        let effects = [combat_commit, effect.broadcast(event.CombatRoundPoll)]
        #(update, effect.batch(effects))
      }
      False -> {
        let update = Model(..model, room:, is_in_combat: False)
        #(update, combat_commit)
      }
    }
    |> Ok
  }
  case result {
    Ok(response) -> response
    Error(_) -> #(model, effect.EffectNone)
  }
}

fn combat_round_trigger(
  model: Model,
  actions: List(event.CombatPollData),
) -> #(Model, RoomEffect(event.RoomMessage)) {
  // filter participants
  let participants =
    actions
    |> list.flat_map(fn(action) { [action.attacker_id, action.victim_id] })
    |> set.from_list

  // Make sure participants are still in the room
  let characters = model.room.characters
  let participants =
    list.filter_map(characters, fn(character) {
      case set.contains(participants, character.id) {
        True -> Ok(#(character.id, character))
        False -> Error(Nil)
      }
    })
    |> dict.from_list()

  // update participants and generate commits to broadcast
  let CombatRoundTemp(participants:, commits:, continue:) =
    CombatRoundTemp(participants:, commits: [], continue: False)
    |> list.fold(actions, _, round_process_action)

  let update = {
    let characters =
      my_list.update(characters, fn(character) {
        dict.get(participants, character.id)
      })
    let room = world.Room(..model.room, characters:)

    case continue {
      True -> Model(..model, room:, combat_queue: [])
      False -> Model(..model, room:, combat_queue: [], is_in_combat: False)
    }
  }

  let effect =
    event.CombatRound(participants:, commits: list.reverse(commits))
    |> effect.broadcast

  #(update, effect)
}

fn round_process_action(
  temp: CombatRoundTemp,
  action: event.CombatPollData,
) -> CombatRoundTemp {
  let CombatRoundTemp(participants:, commits:, continue:) = temp

  let result = {
    // find and update characters
    // confirm characters are alive
    let event.CombatPollData(victim_id:, attacker_id:, dam_roll:) = action
    use attacker <- try(dict.get(participants, attacker_id))
    use victim <- try(dict.get(participants, victim_id))
    use <- bool.guard(attacker.hp <= 0 || victim.hp <= 0, Error(Nil))
    use <- bool.guard(flag.affect_has(victim.affects, flag.GodMode), Error(Nil))
    let victim = case victim.hp - dam_roll {
      hp if hp > 0 -> world.Mobile(..victim, hp:)
      hp -> world.Mobile(..victim, hp:, fighting: world.NoTarget)
    }

    let attacker = case attacker.fighting {
      world.Fighting(_) if victim.hp <= 0 ->
        Some(world.Mobile(..attacker, fighting: world.NoTarget))

      world.NoTarget if victim.hp > 0 ->
        Some(world.Mobile(..attacker, fighting: world.Fighting(victim_id)))

      _ -> None
    }

    let participants = case attacker {
      Some(update) -> dict.insert(participants, attacker_id, update)
      None -> participants
    }

    let participants = dict.insert(participants, victim_id, victim)

    // prepend commits
    let commits =
      event.CombatPollData(attacker_id:, victim_id:, dam_roll: dam_roll)
      |> list.prepend(commits, _)

    // Continue only if any victims have hp > 0
    let continue = continue || victim.hp > 0

    Ok(CombatRoundTemp(participants:, commits:, continue:))
  }

  case result {
    Ok(response) -> response
    Error(_) -> temp
  }
}

fn combat_slay(
  model: Model,
  event: Event(CharacterToRoomEvent, CharacterMessage),
  victim: event.SearchTerm(Mobile),
) -> #(Model, RoomEffect(CharacterMessage)) {
  let characters = model.room.characters
  let result = {
    use victim <- try(find_local_character(characters, victim))
    use <- bool.guard(
      flag.affect_has(victim.affects, flag.GodMode),
      Error(world.GodMode),
    )
    let damage = victim.hp_max * 6
    let victim = world.Mobile(..victim, hp: victim.hp - damage)
    let attacker = event.acting_character

    let update = {
      let characters =
        my_list.update(characters, update_character(_, victim.id, victim))
      let room = world.Room(..model.room, characters:)
      Model(..model, room:)
    }

    let effect =
      event.CombatCommitData(victim:, attacker:, damage:)
      |> event.CombatCommit
      |> effect.broadcast

    Ok(#(update, effect))
  }

  case result {
    Ok(update) -> update
    Error(reason) -> {
      let effect = effect.send_character(event.from, event.ActFailed(reason))
      #(model, effect)
    }
  }
}

fn character_keyword_matches(character: world.Mobile, term: String) -> Bool {
  list.any(character.keywords, fn(keyword) { term == keyword })
}

fn find_local_exit(
  exits: List(world.RoomExit),
  direction: world.Direction,
) -> Result(world.RoomExit, world.ErrorRoomRequest) {
  list.find(exits, fn(exit) { exit.keyword == direction })
  |> result.replace_error(world.UnknownExit(direction))
}

fn item_keyword_matches(item: world.ItemInstance, search_term: String) {
  list.any(item.keywords, fn(keyword) { keyword == search_term })
}

// Confirm exit is accessible
fn can_access(exit: world.RoomExit) -> Result(Nil, world.ErrorRoomRequest) {
  case exit.door {
    Some(door) ->
      case door.state {
        world.Open -> Ok(Nil)
        world.Closed -> Error(world.DoorErr(world.DoorClosed))
      }

    None -> Ok(Nil)
  }
}

fn is_player(mobile: world.Mobile) -> Bool {
  case mobile.template_id {
    world.Player(_) -> True
    world.Npc(_) -> False
  }
}

fn is_pvp(attacker: Mobile, victim: Mobile) -> Bool {
  case attacker.template_id, victim.template_id {
    world.Player(_), world.Player(_) -> True
    _, _ -> False
  }
}

fn find_local_character(
  characters: List(Mobile),
  search_term: event.SearchTerm(Mobile),
) -> Result(Mobile, world.ErrorRoomRequest) {
  let matches = case search_term {
    event.Keyword(term) -> fn(character: world.Mobile) {
      list.any(character.keywords, fn(keyword) { term == keyword })
    }
    event.SearchId(id) -> fn(character: world.Mobile) { id == character.id }
  }

  list.find(characters, matches)
  |> result.replace_error(world.CharacterLookupFailed)
}

fn find_local_item(
  items: List(world.ItemInstance),
  term: String,
) -> Result(world.ItemInstance, Nil) {
  list.find(items, fn(item) {
    list.any(item.keywords, fn(keyword) { term == keyword })
  })
}

fn find_local_xdesc(
  xdescs: List(world.ExtraDesc),
  term: String,
) -> Result(world.ExtraDesc, Nil) {
  list.find(xdescs, fn(xdesc) {
    list.any([xdesc.short, ..xdesc.keywords], fn(keyword) { term == keyword })
  })
}

fn update_character(
  character: Mobile,
  id: StringId(Mobile),
  update: Mobile,
) -> Result(Mobile, Nil) {
  case character.id == id {
    True -> Ok(update)
    False -> Error(Nil)
  }
}

// Checks if there is already an instance of the item template
//
fn is_item_present(
  instances: List(world.ItemInstance),
  item_instance: world.ItemInstance,
) -> Bool {
  let item_id = world.item_id(item_instance)
  list.any(instances, fn(instance) { world.item_id(instance) == item_id })
}
