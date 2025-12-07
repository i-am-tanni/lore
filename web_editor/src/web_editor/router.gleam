import gleam/bit_array
import gleam/bool
import gleam/erlang/process
import gleam/http.{Get, Post}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result.{try}
import gleam/string
import lustre/attribute
import lustre/element
import lustre/element/html
import pog
import web_editor/middleware
import web_editor/sql
import wisp.{type Request, type Response}

const char_0 = 48

const char_9 = 57

pub type Room {
  Room(data: sql.RoomGetRow, exits: List(sql.ExitGetRow))
}

pub type Zone {
  Zone(zone: sql.ZoneGetRow, rooms: List(sql.ZoneRoomsGetRow))
}

pub type RoomInsert {
  RoomInsert(
    zone_id: Int,
    name: String,
    description: String,
    symbol: String,
    x: Int,
    y: Int,
    z: Int,
  )
}

type ExitInsert {
  ExitInsert(
    from_room_id: Int,
    to_room_id: Int,
    exit_keyword: Direction,
    door: Option(DoorInsert),
  )
}

pub type Error {
  Database(pog.QueryError)
  FormDataMissing(String)
  NotFound(String)
  WrongType(String)
}

pub type Direction {
  North
  South
  East
  West
}

pub type DoorInsert {
  DoorInsert(access_state: String)
}

/// The HTTP request handler- your application!
///
pub fn handle_request(req: Request, db: process.Name(pog.Message)) -> Response {
  // Apply the middleware stack for this request/response.
  use req <- middleware.middleware(req)

  case wisp.path_segments(req), req.method {
    [], _ -> home_page(req)
    ["r"], Get -> new_room_page(req)
    ["r"], Post -> insert_room(req, db)
    ["r", room_id], Get -> {
      let result = {
        use id <- try(
          string_to_int(room_id)
          |> result.replace_error(WrongType("Invalid room id")),
        )
        let db = pog.named_connection(db)
        use room <- try(query1(sql.room_get(db, id), "Room"))
        use exits <- try(query_many(sql.exit_get(db, id)))
        Ok(Room(data: room, exits:))
      }

      case result {
        Ok(room) -> room_page(req, room)
        Error(error) -> wisp.bad_request(string.inspect(error))
      }
    }

    ["r", _id], Post -> update_room(req, db)
    ["z", zone_id], Get -> {
      let result = {
        use id <- try(
          string_to_int(zone_id)
          |> result.replace_error(WrongType("Invalid zone id")),
        )
        let db = pog.named_connection(db)
        use zone <- try(query1(sql.zone_get(db, id), "Zone"))
        use rooms <- try(query_many(sql.zone_rooms_get(db, id)))
        Ok(Zone(zone:, rooms:))
      }

      case result {
        Ok(zone) -> zone_page(req, zone)
        Error(error) -> wisp.bad_request(string.inspect(error))
      }
    }
    _, _ -> wisp.not_found()
  }
}

fn home_page(req: Request) -> Response {
  use <- wisp.require_method(req, Get)

  html.div([], [
    html.h1([], [html.text("Online Creation")]),
    html.h2([], [html.text("To edit an existing object:")]),
    html.ul([], [html.li([], [html.text("/r/# Loads a room with an id")])]),
    html.h2([], [html.text("To add a new object:")]),
    html.ul([], [
      html.li([], [html.a([attribute.href("/r")], [html.text("New Room")])]),
    ]),
  ])
  |> element.to_document_string
  |> wisp.html_response(200)
}

fn new_room_page(_req: Request) -> Response {
  let css =
    "
      body{
        font-family: monospace;
      }
      .id_readonly{
        background-color: #e0e0e0;
        color: #a0a0a0;
        cursor: not-allowed;
        border: 1px solid #ccc;
      }
      input[type='int']{
        width: 75px;
      }
      input[name='name']{
        width: 500px;
      }
      input[name='symbol']{
        width: 18px;
      }
      .description{
        height: 200px;
        width: 500px;
      }
    "

  element.fragment([
    html.head([], [html.style([], css)]),
    html.div([], [
      html.form([attribute.method("post")], [
        html.label([], [
          html.text("Id:"),
          html.input([
            attribute.type_("int"),
            attribute.class("id_readonly"),
            attribute.name("room_id"),
            attribute.readonly(True),
          ]),
        ]),
        html.label([], [
          html.text("Name:"),
          html.input([
            attribute.type_("int"),
            attribute.name("name"),
            attribute.placeholder("Insert Room Name Here"),
            attribute.required(True),
          ]),
        ]),
        html.div([], [
          html.label([], [html.text("Zone Id:")]),
          html.input([attribute.type_("int"), attribute.name("zone_id")]),
        ]),
        html.div([], [
          html.label([], [html.text("Description:")]),
          html.textarea(
            [
              attribute.name("description"),
              attribute.class("description"),
              attribute.placeholder("Insert room description here."),
              attribute.spellcheck(True),
              attribute.required(True),
            ],
            "",
          ),
        ]),
        html.div([], [
          html.label([], [
            html.text("Symbol:"),
            html.input([
              attribute.type_("text"),
              attribute.name("symbol"),
              attribute.maxlength(1),
              attribute.placeholder("."),
              attribute.required(True),
            ]),
          ]),
          html.label([], [
            html.text("x:"),
            html.input([
              attribute.type_("int"),
              attribute.name("x"),
              attribute.placeholder("0"),
              attribute.required(True),
            ]),
          ]),
          html.label([], [
            html.text("y:"),
            html.input([
              attribute.type_("int"),
              attribute.name("y"),
              attribute.placeholder("0"),
              attribute.required(True),
            ]),
          ]),
          html.label([], [
            html.text("z: "),
            html.input([
              attribute.type_("int"),
              attribute.name("z"),
              attribute.placeholder("0"),
              attribute.required(True),
            ]),
          ]),
        ]),
        html.input([attribute.type_("submit"), attribute.value("Update")]),
      ]),
    ]),
  ])
  |> element.to_document_string()
  |> wisp.html_response(200)
}

fn room_page(_req: Request, room: Room) -> Response {
  let sql.RoomGetRow(
    zone_id,
    room_id:,
    symbol:,
    x:,
    y:,
    z:,
    name:,
    description:,
    zone_name:,
  ) = room.data

  let assert [zone_id, room_id, x, y, z] =
    list.map([zone_id, room_id, x, y, z], int.to_string)

  let assert [name, description, symbol] =
    list.map([name, description, symbol], wisp.escape_html)
  let num_exits = int.to_string(list.length(room.exits))

  let exits =
    list.map(room.exits, fn(exit) {
      let to_room_id = int.to_string(exit.to_room_id)
      let door_symbol = case exit.door_id {
        Some(_) -> "+"
        None -> ""
      }

      html.li([], [
        html.input([
          attribute.type_("checkbox"),
          attribute.value(int.to_string(exit.exit_id)),
          attribute.name("delete_exit_id"),
        ]),
        html.a([attribute.href("/r/" <> to_room_id)], [
          html.text(door_symbol <> exit.keyword),
        ]),
      ])
    })

  let css =
    "body{
        font-family: monospace;
      }
      .id_readonly{
        background-color: #e0e0e0;
        color: #a0a0a0;
        cursor: not-allowed;
        border: 1px solid #ccc;
      }
      .description{
        width: 500px;
        height: 200px;
      }
      input[type='int']{
        width: 75px;
      }
      input[name='name']{
        width: 400px;
      }
      input[name='symbol']{
        width: 18px;
        justify-content: center;
      }
      input[name='num_exits']{
        display: none;
      }
      .exit_list{
        list-style-type: none;
        margin: 15;
        padding: 0;
      }"

  let html =
    html.div([], [
      html.head([], [html.style([], css)]),
      html.body([], [
        html.form([attribute.method("post")], [
          html.p([], [
            html.label([], [
              html.text("Id:"),
              html.input([
                attribute.type_("int"),
                attribute.class("id_readonly"),
                attribute.name("room_id"),
                attribute.readonly(True),
                attribute.value(room_id),
              ]),
            ]),
            html.label([], [
              html.text("Name:"),
              html.input([
                attribute.type_("text"),
                attribute.name("name"),
                attribute.required(True),
                attribute.value(name),
              ]),
            ]),
          ]),
          html.p([], [
            html.label([], [
              html.text("Zone Id:"),
              html.input([
                attribute.type_("int"),
                attribute.name("zone_id"),
                attribute.value(zone_id),
              ]),
            ]),
            html.label([], [
              html.text("Zone Name:"),
              html.input([
                attribute.type_("text"),
                attribute.name("zone_name"),
                attribute.required(True),
                attribute.value(zone_name),
                attribute.readonly(True),
              ]),
            ]),
          ]),
          html.p([], [
            html.label([], [
              html.text("Description:"),
              html.textarea(
                [
                  attribute.type_("text"),
                  attribute.class("description"),
                  attribute.name("description"),
                  attribute.value(description),
                  attribute.maxlength(1024),
                  attribute.required(True),
                ],
                description,
              ),
            ]),
          ]),
          html.div([attribute.title("Click checkbox to delete exit.")], [
            html.text("Exits: Delete?"),
            html.ul([attribute.class("exit_list")], exits),
          ]),
          html.p([], [
            html.label([], [
              html.text("Symbol: "),
              html.input([
                attribute.type_("text"),
                attribute.name("symbol"),
                attribute.maxlength(1),
                attribute.value(symbol),
                attribute.required(True),
              ]),
            ]),
            html.label([], [
              html.text(" x: "),
              html.input([
                attribute.type_("int"),
                attribute.name("x"),
                attribute.value(x),
                attribute.required(True),
              ]),
            ]),
            html.label([], [
              html.text(" y: "),
              html.input([
                attribute.type_("int"),
                attribute.name("y"),
                attribute.value(y),
                attribute.required(True),
              ]),
            ]),
            html.label([], [
              html.text(" z: "),
              html.input([
                attribute.type_("int"),
                attribute.name("z"),
                attribute.value(z),
                attribute.required(True),
              ]),
            ]),
            html.input([
              attribute.type_("int"),
              attribute.name("num_exits"),
              attribute.class("hidden"),
              attribute.value(num_exits),
            ]),
          ]),
          html.p([], [
            html.fieldset([], [
              html.legend([], [html.text("Extend Exits?")]),
              html.p([], [
                html.label([], [
                  html.text("Bi-directional? "),
                  html.input([
                    attribute.type_("checkbox"),
                    attribute.id("is_two_way_exit"),
                    attribute.name("is_two_way_exit"),
                    attribute.value("True"),
                    attribute.checked(True),
                  ]),
                ]),
                html.label([], [
                  html.text(" To Room Id "),
                  html.input([
                    attribute.type_("int"),
                    attribute.id("to_room_id"),
                    attribute.name("to_room_id"),
                  ]),
                ]),
                html.label([], [
                  html.text(" Exit Keyword "),
                  html.select(
                    [
                      attribute.id("exit_keyword"),
                      attribute.name("exit_keyword"),
                    ],
                    [
                      html.option([attribute.value("north")], "North"),
                      html.option([attribute.value("south")], "south"),
                      html.option([attribute.value("east")], "east"),
                      html.option([attribute.value("west")], "west"),
                    ],
                  ),
                ]),
                html.label([], [
                  html.text(" Door"),
                  html.input([
                    attribute.type_("checkbox"),
                    attribute.id("door"),
                    attribute.name("is_door"),
                    attribute.value("True"),
                  ]),
                ]),
              ]),
            ]),
            html.input([attribute.type_("submit"), attribute.value("Update")]),
          ]),
        ]),
      ]),
    ])
    |> element.to_document_string()

  wisp.ok()
  |> wisp.html_body(html)
}

fn zone_page(_req: Request, zone: Zone) -> Response {
  let rooms =
    list.map(zone.rooms, fn(room) {
      let room_id = int.to_string(room.room_id)
      html.li([], [
        html.a([attribute.href("/r/" <> room_id)], [
          html.text(room_id <> "-" <> room.name),
        ]),
      ])
    })

  let html =
    html.div([], [html.text("Rooms:"), html.ul([], rooms)])
    |> element.to_string

  wisp.ok()
  |> wisp.html_body(html)
}

fn insert_room(req: Request, db: process.Name(pog.Message)) -> Response {
  use formdata <- wisp.require_form(req)
  let db = pog.named_connection(db)
  let result = {
    use zone_id <- try(form_get_int(formdata, "zone_id"))
    use name <- try(form_get(formdata, "name"))
    use desc <- try(form_get(formdata, "description"))
    use symbol <- try(form_get(formdata, "symbol"))
    use x <- try(form_get_int(formdata, "x"))
    use y <- try(form_get_int(formdata, "y"))
    use z <- try(form_get_int(formdata, "z"))
    use sql.RoomInsertRow(room_id) <- try(query1(
      sql.room_insert(db, zone_id, name, desc, symbol, x, y, z),
      "Room Id",
    ))
    let room_id = int.to_string(room_id)
    let success =
      "<a href='/r/" <> room_id <> "'>Inserted room id #" <> room_id <> "!</a>"
    Ok(success)
  }

  case result {
    Ok(content) -> {
      wisp.ok()
      |> wisp.html_body(content)
    }

    Error(error) -> wisp.bad_request(string.inspect(error))
  }
}

fn update_room(req: Request, db: process.Name(pog.Message)) -> Response {
  use formdata <- wisp.require_form(req)
  let db = pog.named_connection(db)
  let result = {
    use room_id <- try(form_get(formdata, "room_id"))
    let assert Ok(id) = string_to_int(room_id)
    use zone_id <- try(form_get_int(formdata, "zone_id"))
    use name <- try(form_get(formdata, "name"))
    use desc <- try(form_get(formdata, "description"))
    use symbol <- try(form_get(formdata, "symbol"))
    use x <- try(form_get_int(formdata, "x"))
    use y <- try(form_get_int(formdata, "y"))
    use z <- try(form_get_int(formdata, "z"))
    let to_room_id = form_get_int(formdata, "to_room_id")
    use _ <- try(
      query0(sql.room_update(db, id, zone_id, name, desc, symbol, x, y, z)),
    )

    // Delete any exits
    list.key_filter(formdata.values, "delete_exit_id")
    |> list.filter_map(string_to_int)
    |> list.filter_map(fn(id) {
      query1(sql.exit_deactivate(db, id), "Other Exit Side Info")
    })
    |> list.each(fn(other_exit_side_info) {
      let sql.ExitDeactivateRow(exit_id:, keyword:, to_room_id:) =
        other_exit_side_info
      let keyword =
        keyword
        |> string_to_direction
        |> direction_opposite
        |> direction_to_string

      // deactivate any associated doors
      use _ <- try(query1(
        sql.exit_deactivate_other_side(db, to_room_id, keyword),
        "Nothing",
      ))
      use doors <- try(query_many(sql.door_get_from_exit_id(db, exit_id)))
      list.map(doors, fn(door) { door.door_id })
      |> list.each(sql.door_deactivate(db, _))
      |> Ok
    })

    let success = "<a href='/r/" <> room_id <> "'>Updated!</a>"
    // Add exit if inputted
    case to_room_id {
      Ok(to_room_id) if to_room_id != 0 -> {
        use exit_keyword <- try(
          form_get(formdata, "exit_keyword") |> result.map(string_to_direction),
        )
        let door = case form_get_bool(formdata, "door") {
          True -> Some(DoorInsert("closed"))
          False -> None
        }
        use _ <- try(new_exit(
          db,
          ExitInsert(id, to_room_id, exit_keyword:, door:),
        ))
        echo formdata as "formdata"
        use <- bool.guard(
          !form_get_bool(formdata, "is_two_way_exit"),
          Ok(success),
        )
        // If the exit is two-way, insert other side
        use _ <- result.try(new_exit(
          db,
          ExitInsert(
            to_room_id,
            id,
            exit_keyword: direction_opposite(exit_keyword),
            door:,
          ),
        ))
        Ok(success)
      }

      _ -> Ok(success)
    }
  }

  case result {
    Ok(content) -> {
      wisp.ok()
      |> wisp.html_body(content)
    }

    Error(error) -> wisp.bad_request(string.inspect(error))
  }
}

fn direction_to_string(direction: Direction) -> String {
  case direction {
    North -> "north"
    South -> "south"
    East -> "east"
    West -> "west"
  }
}

fn string_to_direction(string: String) -> Direction {
  case string {
    "north" -> North
    "south" -> South
    "east" -> East
    "west" -> West
    _ -> North
  }
}

fn direction_opposite(keyword: Direction) -> Direction {
  case keyword {
    North -> South
    South -> North
    East -> West
    West -> East
  }
}

fn string_to_int(s: String) -> Result(Int, Nil) {
  case bit_array.from_string(s) {
    <<"-", rest:bits>> ->
      string_to_int_loop(rest, 0)
      |> result.map(fn(x) { -x })

    s -> string_to_int_loop(s, 0)
  }
}

fn string_to_int_loop(s: BitArray, acc: Int) -> Result(Int, Nil) {
  case s {
    <<>> -> Ok(acc)
    <<"-", rest:bits>> -> string_to_int_loop(rest, -acc)
    <<x:size(8), rest:bits>> if x >= char_0 && x <= char_9 ->
      string_to_int_loop(rest, acc * 10 + { x - char_0 })
    _ -> Error(Nil)
  }
}

fn new_exit(db: pog.Connection, data: ExitInsert) -> Result(Nil, Error) {
  let ExitInsert(from_room_id:, to_room_id:, exit_keyword:, door:) = data
  let exit_keyword = direction_to_string(exit_keyword)
  case door {
    Some(_door_data) -> {
      use sql.DoorInsertRow(door_id) <- try(query1(
        sql.door_insert(db, sql.Closed),
        "door_id",
      ))
      use _ <- try(
        query0(sql.exit_insert_w_door(
          db,
          from_room_id,
          to_room_id,
          exit_keyword,
          door_id,
        )),
      )
      Ok(Nil)
    }

    None -> {
      use _ <- try(
        query0(sql.exit_insert(db, from_room_id, to_room_id, exit_keyword)),
      )
      Ok(Nil)
    }
  }
}

fn form_get(formdata: wisp.FormData, key: String) -> Result(String, Error) {
  list.key_find(formdata.values, key)
  |> result.replace_error(FormDataMissing(key))
}

fn form_get_int(formdata: wisp.FormData, key: String) -> Result(Int, Error) {
  use int <- try(
    list.key_find(formdata.values, key)
    |> result.replace_error(FormDataMissing(key)),
  )
  use int <- try(
    string_to_int(int) |> result.replace_error(FormDataMissing(key)),
  )
  Ok(int)
}

fn form_get_bool(formdata: wisp.FormData, key: String) -> Bool {
  echo formdata.values
  list.key_find(formdata.values, key) == Ok("True")
}

fn query0(result: Result(pog.Returned(a), pog.QueryError)) -> Result(Nil, Error) {
  use returned <- try(result.map_error(result, Database))
  case returned {
    pog.Returned(count: 1, rows: []) -> Ok(Nil)
    _ -> Error(NotFound("???"))
  }
}

fn query1(
  result: Result(pog.Returned(a), pog.QueryError),
  expected expected: String,
) -> Result(a, Error) {
  use returned <- try(result.map_error(result, Database))
  case returned {
    pog.Returned(count: 1, rows: [returned]) -> Ok(returned)
    _ -> Error(NotFound(expected))
  }
}

fn query_many(
  result: Result(pog.Returned(a), pog.QueryError),
) -> Result(List(a), Error) {
  use pog.Returned(rows:, ..) <- try(result.map_error(result, Database))
  Ok(rows)
}
