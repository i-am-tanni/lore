//// A response builder for a request received by a character.
//// The outgoing response is expressed as a list of renders, events, and 
//// updates to character state.
//// 

import gleam/list
import gleam/option.{type Option, None, Some}

import ming/character/controller.{type Flash}
import ming/character/view.{type View}
import ming/server/output.{type Text}
import ming/world.{type ControllerMessage, type Mobile, type RoomEvent}
import ming/world/id

/// A type that wraps the character state and aggregates a response
/// to be returned to the calling controller.
/// 
pub opaque type Conn {
  Conn(
    character: Mobile,
    flash: Flash,
    events: List(EventToSend),
    output: List(Text),
    update_character: Option(Mobile),
    update_flash: Option(Flash),
    next_controller: Option(NextController),
    halt: Bool,
    request_id: String,
  )
}

pub type EventToSend {
  ToCharacter(world.CharacterEvent, keyword: String)
  ToRoom(RoomEvent)
}

/// A response to the request received, processed by the character actor.
/// 
pub type Response {
  Response(
    updated_character: Option(Mobile),
    updated_flash: Option(Flash),
    next_controller: Option(NextController),
    events: List(EventToSend),
    output: List(Text),
    halt: Bool,
    request_id: String,
  )
}

/// A staged transition to a new controller.
/// 
pub type NextController {
  /// The init function takes a Conn and a new flash as arguments, but the old
  /// flash still accessible via `conn.get_flash()`
  /// 
  NextController(
    flash: Flash,
    init: fn(Conn, Flash) -> Conn,
    recv: fn(Conn, ControllerMessage) -> Conn,
  )
}

/// Generates a new conn. This is the handle generated when a request
/// is received by the character process for the purpose of building a response.
/// 
pub fn new(character_context: Mobile, flash: Flash) -> Conn {
  Conn(
    character: character_context,
    flash: flash,
    events: [],
    output: [],
    request_id: id.generate(),
    update_flash: None,
    update_character: None,
    next_controller: None,
    halt: False,
  )
}

/// Returns mobile context. The given boolean determines if staged data is
/// returned or not.
/// 
pub fn get_character(conn: Conn, updated: Bool) -> Mobile {
  case updated, conn.update_character {
    True, Some(updated_character) -> updated_character
    _, _ -> conn.character
  }
}

/// Stages changes to the character state.
/// 
pub fn put_character(conn: Conn, character: Mobile) -> Conn {
  Conn(..conn, update_character: Some(character))
}

/// Stages a change in controller.
/// 
pub fn put_controller(conn: Conn, next: NextController) -> Conn {
  Conn(..conn, next_controller: Some(next))
}

/// Returns flash memory
/// 
pub fn get_flash(conn: Conn) -> Flash {
  case conn.update_flash {
    Some(updated_flash) -> updated_flash
    None -> conn.flash
  }
}

/// Updates the current flash memory for the current controller
/// 
pub fn put_flash(conn: Conn, flash: Flash) -> Conn {
  Conn(..conn, update_flash: Some(flash))
}

/// Renders text without a newline.
/// 
pub fn render(conn: Conn, view: View) -> Conn {
  let text = output.Text(text: view.to_string_tree(view), newline: False)
  Conn(..conn, output: [text, ..conn.output])
}

/// Renders text with a newline.
/// 
pub fn renderln(conn: Conn, view: View) -> Conn {
  let text = output.Text(text: view.to_string_tree(view), newline: True)
  Conn(..conn, output: [text, ..conn.output])
}

/// Notifies the process owner to terminate at the end of the response.
/// 
pub fn terminate(conn: Conn) -> Conn {
  Conn(..conn, halt: True)
}

/// Transforms a conn into a completed response to be processed by the caller.
/// 
pub fn to_response(conn: Conn) -> Response {
  Response(
    updated_character: conn.update_character,
    updated_flash: conn.update_flash,
    next_controller: conn.next_controller,
    events: list.reverse(conn.events),
    output: list.reverse(conn.output),
    halt: conn.halt,
    request_id: conn.request_id,
  )
}
