import gleam/bit_array
import gleam/int
import gleam/list
import gleam/option.{type Option}
import lore/character/pronoun

pub type RoomTemplate

/// An id from the database.
///
pub type Id(a) {
  Id(Int)
}

/// An id generated during runtime.
///
pub type StringId(a) {
  StringId(String)
}

pub type Vote(reason) {
  Approve
  Reject(reason)
}

pub type ChatChannel {
  General
}

pub type Zone {
  Zone(
    id: Id(Zone),
    name: String,
    rooms: List(Room),
    spawn_groups: List(SpawnGroup),
  )
}

pub type Room {
  Room(
    id: Id(Room),
    zone_id: Id(Zone),
    symbol: String,
    x: Int,
    y: Int,
    z: Int,
    name: String,
    description: String,
    exits: List(RoomExit),
    characters: List(Mobile),
    items: List(ItemInstance),
  )
}

pub type Direction {
  North
  South
  East
  West
  Up
  Down
  CustomExit(String)
}

pub type RoomExit {
  RoomExit(
    id: Id(RoomExit),
    keyword: Direction,
    from_room_id: Id(Room),
    to_room_id: Id(Room),
    door: Option(Door),
  )
}

pub type Door {
  Door(id: Id(Door), state: AccessState)
}

pub type AccessState {
  Open
  Closed
}

/// Public mobile data relating to a mobile instance.
///
pub type Mobile {
  Mobile(
    id: StringId(Mobile),
    room_id: Id(Room),
    template_id: TemplateId,
    name: String,
    keywords: List(String),
    pronouns: pronoun.PronounChoice,
    short: String,
  )
}

/// Private internal mobile data.
///
pub type MobileInternal {
  MobileInternal(
    id: StringId(Mobile),
    room_id: Id(Room),
    template_id: TemplateId,
    name: String,
    keywords: List(String),
    pronouns: pronoun.PronounChoice,
    short: String,
    inventory: List(ItemInstance),
  )
}

pub type Npc

pub type Player

pub type TemplateId {
  Npc(template_id: Id(Npc))
  Player(template_id: Id(Player))
}

pub type Item {
  Item(
    id: Id(Item),
    keywords: List(String),
    name: String,
    short: String,
    long: String,
  )
}

pub type Load {
  Loaded(Item)
  Loading(Id(Item))
}

/// An instance of an item. Uses a flyweight pattern to retrieve data.
///
pub type ItemInstance {
  ItemInstance(id: StringId(ItemInstance), keywords: List(String), item: Load)
}

pub type SpawnGroup {
  /// - is_despawn_on_reset: determines if the spawn group will despawn all
  /// active instances on reset or whether it will only spawn inactives
  /// - reset_freq: in milliseconds, how often the spawn group will reset
  ///
  SpawnGroup(
    id: Id(SpawnGroup),
    mob_members: List(MobSpawn),
    mob_instances: List(#(Id(MobSpawn), StringId(Mobile))),
    item_members: List(ItemSpawn),
    item_instances: List(#(Id(ItemSpawn), StringId(ItemInstance))),
    reset_freq: Int,
    is_enabled: Bool,
    is_despawn_on_reset: Bool,
  )
}

pub type MobSpawn {
  MobSpawn(spawn_id: Id(MobSpawn), mobile_id: Id(Npc), room_id: Id(Room))
}

pub type ItemSpawn {
  ItemSpawn(spawn_id: Id(ItemSpawn), item_id: Id(Item), room_id: Id(Room))
}

/// Generates random 32 bit base-16 encoded string identifier.
///
/// ## Example
/// ```gleam
/// id.generate()
/// // -> 3D40AD6B
/// ```
///
pub fn generate_id() -> StringId(a) {
  list.range(1, 4)
  |> list.map(fn(_) { <<int.random(256)>> })
  |> bit_array.concat
  |> bit_array.base16_encode
  |> StringId
}

pub type ErrorRoomRequest {
  UnknownExit(direction: Direction)
  RoomLookupFailed(room_id: Id(Room))
  CharacterLookupFailed(keyword: String)
  ItemLookupFailed(keyword: String)
  MoveErr(ErrorMove)
  DoorErr(ErrorDoor)
  NotFound(keyword: String)
}

/// An error type defining all the ways a move from one room to another can fail
///
pub type ErrorMove {
  Unauthorized
  DoorNotOpen(direction: Direction, state: AccessState)
}

pub type ErrorDoor {
  MissingDoor(Direction)
  NoChangeNeeded(AccessState)
  DoorLocked
  DoorClosed
}

pub fn direction_to_string(direction: Direction) -> String {
  case direction {
    North -> "north"
    South -> "south"
    East -> "east"
    West -> "west"
    Up -> "up"
    Down -> "down"
    CustomExit(custom) -> custom
  }
}
