import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option}
import lore/character/flag

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
    xdescs: List(ExtraDesc),
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

/// An extra description that can be revealed via keyword search
pub type ExtraDesc {
  ExtraDesc(short: String, keywords: List(String), text: String)
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

pub type Fighting {
  Fighting(StringId(Mobile))
  NoTarget
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
    pronouns: PronounKind,
    short: String,
    fighting: Fighting,
    affects: flag.Affects,
    hp: Int,
    hp_max: Int,
  )
}

pub type Role {
  Admin
  User
}

pub type Affects {
  Affects(flags: flag.Affects)
}

/// Private internal mobile data.
///
pub type MobileInternal {
  /// ## Private fields
  /// - inventory
  /// - equipment
  MobileInternal(
    id: StringId(Mobile),
    room_id: Id(Room),
    template_id: TemplateId,
    role: Role,
    name: String,
    keywords: List(String),
    inventory: List(ItemInstance),
    equipment: Dict(WearSlot, Wearing),
    pronouns: PronounKind,
    short: String,
    fighting: Fighting,
    affects: Affects,
    hp: Int,
    hp_max: Int,
  )
}

pub type Npc

pub type Player

pub type TemplateId {
  Npc(template_id: Id(Npc))
  Player(template_id: Id(Player))
}

pub type Container(a) {
  Contains(List(a))
  NotContainer
}

pub type WearSlot {
  Arms
  CannotWear
}

pub type Wearing {
  Wearing(ItemInstance)
  EmptySlot
}

pub type Item {
  Item(
    id: Id(Item),
    keywords: List(String),
    name: String,
    short: String,
    long: String,
    wear_slot: WearSlot,
    contains: Container(Id(Item)),
  )
}

pub type Load {
  Loaded(Item)
  Loading(Id(Item))
}

/// An instance of an item. Uses a flyweight pattern to retrieve data.
///
pub type ItemInstance {
  ItemInstance(
    id: StringId(ItemInstance),
    keywords: List(String),
    item: Load,
    contains: Container(ItemInstance),
    was_touched: Bool,
  )
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

/// Data related to spawning a mobile by a SpawnGroup
///
pub type MobSpawn {
  MobSpawn(spawn_id: Id(MobSpawn), mobile_id: Id(Npc), room_id: Id(Room))
}

/// Data related to spawning an item by a SpawnGroup
///
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

pub type ErrorItem {
  UnknownItem(search_term: String, verb: String)
  CannotBeWorn(item: Item)
  CannotWield(item: Item)
  WearSlotFull(wear_slot: WearSlot, item: Item)
  WearSlotMissing(wear_slot: WearSlot)
  InvalidItemId(item_id: Id(Item))
}

pub type ErrorRoomRequest {
  UnknownExit(direction: Direction)
  RoomLookupFailed(room_id: Id(Room))
  CharacterLookupFailed
  ItemLookupFailed(keyword: String)
  MoveErr(ErrorMove)
  DoorErr(ErrorDoor)
  NotFound(keyword: String)
  PvpForbidden
  GodMode
}

pub type ErrorMove {
  Unauthorized
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

/// Returns a random number between 1 and max
///
pub fn random(max: Int) -> Int {
  int.random(max - 1) + 1
}

/// This prevents leaking private character information via events.
///
pub fn trim_character(character: MobileInternal) -> Mobile {
  let MobileInternal(
    id:,
    room_id:,
    template_id:,
    name:,
    keywords:,
    pronouns:,
    short:,
    hp:,
    hp_max:,
    fighting:,
    ..,
  ) = character

  let Affects(flags: affects) = character.affects

  Mobile(
    id:,
    room_id:,
    template_id:,
    name:,
    keywords:,
    pronouns:,
    short:,
    fighting:,
    affects:,
    hp:,
    hp_max:,
  )
}

pub fn mobile_identity() -> Mobile {
  Mobile(
    id: StringId("0"),
    room_id: Id(0),
    template_id: Npc(Id(0)),
    name: "",
    keywords: [],
    pronouns: PronounNeutral,
    short: "",
    fighting: NoTarget,
    affects: flag.Affects(0),
    hp: 0,
    hp_max: 0,
  )
}

pub fn is_player(mobile: Mobile) -> Bool {
  case mobile.template_id {
    Player(_) -> True
    Npc(_) -> False
  }
}

pub fn item_id(instance: ItemInstance) -> Id(Item) {
  case instance.item {
    Loading(item_id) -> item_id
    Loaded(Item(id:, ..)) -> id
  }
}

pub fn affects_init() -> Affects {
  Affects(flags: flag.Affects(0))
}

pub type Pronoun {
  /// Note: These are only masculine because he/him/his/himself is clearer
  /// than she/her/her/herself
  Pronoun(he: String, him: String, his: String, himself: String)
}

pub type PronounKind {
  Feminine
  Masculine
  PronounNeutral
}

pub fn pronouns(choice: PronounKind) -> Pronoun {
  case choice {
    Feminine -> feminine
    Masculine -> masculine
    PronounNeutral -> neutral
  }
}

const feminine = Pronoun(he: "she", him: "her", his: "her", himself: "herself")

const masculine = Pronoun(he: "he", him: "him", his: "his", himself: "himself")

const neutral = Pronoun(
  he: "they",
  him: "them",
  his: "their",
  himself: "themself",
)
