//// An actor for generating ascii maps.
////

import gleam/bool
import gleam/dict.{type Dict}
import gleam/erlang/process
import gleam/list
import gleam/otp/actor
import gleam/pair
import gleam/result
import gleam/set.{type Set}
import gleam/string
import gleam/string_tree.{type StringTree}
import logging
import lore/world.{type Id, type Room}

pub type Message {
  RenderMiniMap(caller: process.Subject(List(StringTree)), room_id: Id(Room))
  InsertPath(from: Id(Room), to: Id(Room))
  DeletePath(from: Id(Room), to: Id(Room))
}

type State {
  State(nodes: Dict(Id(Room), MapNode), graph: Digraph)
}

type MapNode {
  MapNode(id: Id(Room), symbol: String, x: Int, y: Int, z: Int)
}

type MapEdge {
  MapEdge(from: Id(Room), to: Id(Room))
}

type Digraph

type DoNotLeak

//
// Constants
//

const xsize = 5

const xmin = 0

const ymin = 0

// xsize - 1
const xmax = 4

// ysize - 1
const ymax = 4

// xmax * ysize + ymax
const index_max = 24

const center_x = 2

const center_y = 2

const center_index = 12

const max_depth = 4

const you_are_here = "&123@0;"

const default_symbol = " "

// The default map render if an error is encountered
const uncharted = [
  " ", " ", " ", " ", " ", " ", " ", " ", " ", " ", " ", " ", "&123@0;", " ",
  " ", " ", " ", " ", " ", " ", " ", " ", " ", " ", " ",
]

/// Generates a 5x5 map where `<>` is the player's position
/// 
pub fn render_mini_map(
  name: process.Name(Message),
  room_id: Id(Room),
) -> List(StringTree) {
  process.named_subject(name)
  |> process.call(200, RenderMiniMap(_, room_id:))
}

pub fn start(
  name: process.Name(Message),
  zones: List(world.Zone),
) -> Result(actor.Started(process.Subject(Message)), actor.StartError) {
  let nodes =
    list.flat_map(zones, fn(zone) {
      list.map(zone.rooms, fn(room) {
        let world.Room(id:, symbol:, x:, y:, z:, ..) = room
        MapNode(id:, symbol:, x:, y:, z:)
      })
    })

  let edges = {
    use zone <- list.flat_map(zones)
    use room <- list.flat_map(zone.rooms)
    use exit <- list.map(room.exits)
    MapEdge(from: exit.from_room_id, to: exit.to_room_id)
  }

  actor.new_with_initialiser(100, fn(self) { init(self, nodes, edges) })
  |> actor.named(name)
  |> actor.on_message(recv)
  |> actor.start
}

fn init(
  self: process.Subject(Message),
  nodes: List(MapNode),
  edges: List(MapEdge),
) -> Result(actor.Initialised(State, Message, process.Subject(Message)), String) {
  let graph = digraph_new()
  list.each(nodes, fn(node) { digraph_add_vertex(graph, node.id) })
  list.each(edges, fn(edge) { digraph_add_edge(graph, edge.from, edge.to) })

  let nodes =
    list.map(nodes, fn(node) { #(node.id, node) })
    |> dict.from_list()

  let selector = process.new_selector() |> process.select(self)

  State(graph:, nodes:)
  |> actor.initialised
  |> actor.selecting(selector)
  |> actor.returning(self)
  |> Ok
}

fn recv(state: State, msg: Message) -> actor.Next(State, Message) {
  case msg {
    RenderMiniMap(caller:, room_id:) ->
      process.send(caller, mini_map(state, room_id))

    InsertPath(from:, to:) -> {
      let nodes = state.nodes
      let result = {
        use <- bool.guard(dict.has_key(nodes, from), Error(from))
        use <- bool.guard(dict.has_key(nodes, to), Error(to))
        Ok(digraph_add_edge(state.graph, from, to))
      }

      case result {
        Ok(_) -> Nil
        Error(missing) -> {
          let error =
            "Mapper is missing room id " <> string.inspect(missing) <> " ."
          logging.log(logging.Error, error)
        }
      }
    }

    DeletePath(from:, to:) -> digraph_del_path(state.graph, from, to)
  }

  actor.continue(state)
}

// Render a 5x5 mini-map where each map symbol is a character pair
fn mini_map(state: State, room_id: Id(Room)) -> List(StringTree) {
  let State(nodes:, graph:) = state
  let result = {
    use MapNode(x:, y:, z:, ..) as center <- result.try(dict.get(nodes, room_id))
    // get neighbors on this z-plane and filter only those that will be displayed,
    // convert to a dict and use that to render the map where empty coords will
    // display the default symbol.
    neighbors(graph, nodes, z, room_id)
    |> list.filter_map(fn(neighbor) {
      // convert absolute coords to mini-map coords
      let x = neighbor.x - x + center_x
      let y = y - neighbor.y + center_y
      // filter out any coords outside of the display window
      use <- bool.guard(
        x > xmax || y > ymax || x < xmin || y < ymin,
        Error(Nil),
      )
      // place into a dict keyed by index hash
      let index2d = y * xsize + x
      Ok(#(index2d, neighbor))
    })
    |> list.prepend(#(center_index, MapNode(..center, symbol: you_are_here)))
    |> dict.from_list()
    // Orders vector symbols by index and inserts the default where there is 
    // no symbol.
    //
    // index references:
    //   00 01 02 03 04
    //   05 06 07 08 09
    //   10 11 12 13 14
    //   15 16 17 18 19
    //   20 21 22 23 24
    |> fn(render_data: Dict(Int, MapNode)) {
      list.map(list.range(0, index_max), fn(i) {
        case dict.get(render_data, i) {
          Ok(vertex) -> vertex.symbol
          Error(Nil) -> default_symbol
        }
      })
    }
    |> Ok
  }

  result
  |> result.unwrap(uncharted)
  |> list.sized_chunk(5)
  |> list.map(string_tree.from_strings)
}

// Depth first search neighbor ids.
//
fn neighbors(
  graph: Digraph,
  nodes: Dict(Id(Room), MapNode),
  z_coord: Int,
  origin: Id(Room),
) -> List(MapNode) {
  // init accumulator is a tuple pair #(a, b) where:
  // - (a) is a list of vertexes to visit keyed by room_id
  // - (b) is a set of previously visited rooms
  //
  let visiting: List(Id(Room)) = [origin]
  let visited: Set(Id(Room)) = set.new()
  // for each iteration (depth) up to the max depth
  list.map_fold(list.range(0, max_depth), #(visiting, visited), fn(acc, _) {
    case acc {
      #(visiting, visited) if visiting != [] -> {
        // first, update visited so the current visiting members are visited
        // only once.
        let visited = set.union(set.from_list(visiting), visited)

        // for each room, get list of neighbor ids and filter unvisited
        // on this z-plane
        let neighbors: List(MapNode) =
          {
            use room_id <- list.flat_map(visiting)
            use neighbor_id <- list.filter_map(out_neighbors(graph, room_id))
            use vertex <- result.try(dict.get(nodes, neighbor_id))
            // reject if neighbor_id is on a different z-plane or already 
            // visited.
            use <- bool.guard(
              vertex.z != z_coord || set.contains(visited, neighbor_id),
              Error(Nil),
            )
            // ...else add to the list of nodes to visit the next iteration
            Ok(vertex)
          }
          |> list.unique()

        let to_visit: List(Id(Room)) =
          list.map(neighbors, fn(vertex) { vertex.id })

        #(#(to_visit, visited), neighbors)
      }

      _else_nothing_left_to_visit -> #(acc, [])
    }
  })
  |> pair.second()
  // each member is the list of neighbors for each iteration of the loop
  // and we'll flatten to get a list of all neighbors
  |> list.flatten()
}

@external(erlang, "digraph", "new")
fn digraph_new() -> Digraph

@external(erlang, "digraph", "add_vertex")
fn digraph_add_vertex(graph: Digraph, key: a) -> DoNotLeak

@external(erlang, "digraph", "add_edge")
fn digraph_add_edge(graph: Digraph, a: a, b: a) -> DoNotLeak

@external(erlang, "digraph", "del_path")
fn digraph_del_path(graph: Digraph, a: a, b: a) -> Nil

@external(erlang, "digraph", "out_neighbours")
fn out_neighbors(graph: Digraph, key: a) -> List(a)
