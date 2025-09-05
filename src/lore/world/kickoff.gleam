//// A process for loading zones into memory and then spinning them up
//// into processes.
//// 

import gleam/list
import gleam/option.{Some}
import gleam/otp/static_supervisor
import gleam/otp/supervision.{worker}
import lore/world.{Door, Id, Room, RoomExit, Zone}
import lore/world/items
import lore/world/mapper
import lore/world/room
import lore/world/system_tables
import lore/world/zone

const test_item = world.Item(
  name: "a pair of &WP&Pr&Wo&Pg&Wr&Pa&Wm&Pm&We&Pr &WS&Po&Wc&Pk&Ws0;",
  keywords: ["socks", "programmer"],
  short: "A pair of striped socks have been discarded here.",
  long: "A legendary pair of long socks said to improve programming prowess.",
  id: Id(1),
)

const zones = [
  Zone(
    id: Id(1),
    name: "Test Zone",
    items: [test_item],
    rooms: [
      Room(
        id: Id(1),
        template_id: Id(1),
        zone_id: Id(1),
        symbol: ".",
        x: 0,
        y: 0,
        z: 0,
        name: "North Room",
        description: "It's colder up here.",
        exits: [
          RoomExit(
            id: Id(1),
            keyword: world.South,
            from_room_id: Id(1),
            to_room_id: Id(2),
            door: Some(Door(id: Id(1), state: world.Closed)),
          ),
        ],
        characters: [],
        items: [],
      ),
      Room(
        id: Id(2),
        template_id: Id(2),
        zone_id: Id(1),
        symbol: ".",
        x: 0,
        y: -1,
        z: 0,
        name: "South Room",
        description: "It's warmer down here.",
        exits: [
          RoomExit(
            id: Id(1),
            keyword: world.North,
            from_room_id: Id(2),
            to_room_id: Id(1),
            door: Some(Door(id: Id(1), state: world.Closed)),
          ),
        ],
        characters: [],
        items: [
          world.ItemInstance(
            id: world.StringId(""),
            item: world.Loading(Id(1)),
            keywords: ["socks", "programmer"],
          ),
        ],
      ),
    ],
  ),
]

pub fn supervised(
  system_tables: system_tables.Lookup,
) -> supervision.ChildSpecification(static_supervisor.Supervisor) {
  let supervisor = static_supervisor.new(static_supervisor.OneForOne)

  let items = list.flat_map(zones, fn(zone) { zone.items })

  // Add a supervisor per zone and the mapper worker
  list.fold(zones, supervisor, fn(acc, zone) {
    static_supervisor.add(acc, zone_supervised(zone, system_tables))
  })
  |> static_supervisor.add(
    worker(fn() { mapper.start(system_tables.mapper, zones) }),
  )
  |> static_supervisor.add(
    worker(fn() { items.start(system_tables.items, items) }),
  )
  |> static_supervisor.supervised
}

fn zone_supervised(
  zone: world.Zone,
  system_tables: system_tables.Lookup,
) -> supervision.ChildSpecification(static_supervisor.Supervisor) {
  static_supervisor.new(static_supervisor.OneForOne)
  |> static_supervisor.add(worker(fn() { zone.start(zone, system_tables) }))
  |> list.fold(zone.rooms, _, fn(acc, room) {
    static_supervisor.add(acc, worker(fn() { room.start(room, system_tables) }))
  })
  |> static_supervisor.supervised
}
