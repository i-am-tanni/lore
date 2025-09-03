//// An actor for processing I/O from a glisten TCP connection. 
//// Any processed data is forwarded to the owned character.
//// Responses from the owned character are forwarded to the socket.
//// 

import gleam/bit_array
import gleam/bool
import gleam/bytes_tree.{type BytesTree}
import gleam/erlang/process.{type Selector, type Subject}
import gleam/function.{tap}
import gleam/list
import gleam/option.{type Option, Some}
import gleam/otp/actor
import gleam/result
import gleam/set.{type Set}
import gleam/string_tree
import glisten.{Packet, User}
import glisten/tcp
import logging
import lore/character
import lore/server/output
import lore/server/telnet.{Do, Dont, Will, Wont}
import lore/world/event.{type CharacterMessage}
import lore/world/system_tables

const max_input_buffer_size = 1024

// constants for telnet out of band communication

// interpret as command - 
const iac = 255

// end of record telnet option and command
const eor_option = 25

const eor_command = 239

// go-ahead (sent if EOR is not available)
const ga = 249

// will communicates an option is available
const will = 251

// negoatiate about window size
const naws = 31

// do requests an option
const do = 253

// suppress go-ahead
const sga = 3

// echo_option
const echo_option = 1

pub type ProtocolError {
  /// Input sent from non-standard clients may be in a form that is unreadable
  /// by the telnet library. If that is the case, the connection will
  /// disconnect as there is not much point in continuing.
  /// 
  InputUnreadable

  /// If too much data is being sent via sub-negotiation or sub-negotiation
  /// is malformed, than eventually the buffer will overflow resulting in a 
  /// disconnect. This is a guard to prevent a connection from consuming
  /// too much memory.
  /// 
  InputBufferOverflow
}

pub type State {
  /// The state holds a buffer of any unprocessed packet data to be appended
  /// to the next packet received. Any negotiated telnet options are kept
  /// in a set. Whether to the next output should be prepended with a newline
  /// is also tracked. As long as bool continue is true, then the connection
  /// will persist.
  /// 
  /// The endpoint is the actor the connection is sending inputs to and 
  /// receiving outputs from. This could be a character, a puppeted NPC, a bot
  /// API, etc.
  /// 
  State(
    conn: glisten.Connection(character.Outgoing),
    ip_address: String,
    buffer: BitArray,
    options: Set(TelnetOption),
    window_size: WindowSize,
    endpoint: Subject(CharacterMessage),
    newline: Bool,
    continue: Bool,
  )
}

/// The window size may be communicated by the client via NAWS - Negotiate
/// About Window Size. Knowing the window size is useful for server side
/// line wrapping or making other decisions about the output.
/// If the server communicates a window size that is too smal or a size of
/// 0: width and 0:height, the server will consider the size unknown and defer
/// line wrapping to the client.
/// 
pub type WindowSize {
  WindowSize(width: Int, height: Int)
  Unknown
}

/// Telnet options supported by the server
/// 
pub type TelnetOption {
  /// End of Record
  EOR
}

/// Receives a new connection, sends initial telnet negotiation, and 
/// starts a new character actor for the player with the initial controller.
/// 
pub fn init(
  conn: glisten.Connection(character.Outgoing),
  system_tables: system_tables.Lookup,
) -> #(State, Option(Selector(character.Outgoing))) {
  let assert Ok(glisten.ConnectionInfo(ip_address:, ..)) =
    glisten.get_client_info(conn)

  let ip_address = glisten.ip_address_to_string(ip_address)

  logging.log(logging.Info, "New Connection Started: <" <> ip_address <> ">")
  initial_iacs(conn)

  let self = process.new_subject()

  let assert Ok(actor.Started(data: reception, ..)) =
    character.start_reception(self, system_tables)

  let state =
    State(
      conn: conn,
      ip_address: ip_address,
      buffer: <<>>,
      options: set.new(),
      newline: False,
      endpoint: reception,
      window_size: Unknown,
      continue: True,
    )

  let selector =
    process.new_selector()
    |> process.select(self)

  #(state, Some(selector))
}

/// Receives a packet from the connection (Input) or a message from the linked
/// character actor (Output).
/// 
pub fn recv(
  state: State,
  msg: glisten.Message(character.Outgoing),
  conn: glisten.Connection(character.Outgoing),
) -> glisten.Next(State, glisten.Message(character.Outgoing)) {
  let result = case msg {
    Packet(msg) -> handle_packet(state, msg)
    User(character.PushText(text)) -> Ok(push_text(state, text))
    User(character.Reassign(subject:)) -> Ok(State(..state, endpoint: subject))
    User(character.Halt(pid)) -> {
      case process.subject_owner(state.endpoint) {
        // shutdown if this would orphan the protocol from the endpoint
        Ok(endpoint) if pid == endpoint -> Ok(State(..state, continue: False))
        // ..else ignore.
        _ -> Ok(state)
      }
    }
  }

  case result {
    // only continue if continue is set to true
    Ok(state) if state.continue -> glisten.continue(state)
    // otherwise halt
    Ok(_) -> shutdown(conn)
    Error(InputBufferOverflow) -> {
      log_error("Input Buffer Exceeded", state.ip_address)
      shutdown(conn)
    }
    Error(InputUnreadable) -> {
      // No standard mud client should cause this error.
      log_error("Input is Unreadable", state.ip_address)
      shutdown(conn)
    }
  }
}

/// tell caller they can now exit
fn initial_iacs(conn: glisten.Connection(a)) {
  [
    <<iac, will, eor_option>>,
    <<iac, do, naws>>,
    //<<iac, will, sga>>,
  //<<iac, will, echo_option>>,
  ]
  |> bytes_tree.concat_bit_arrays()
  |> push(conn, _)
}

fn handle_packet(state: State, stream: BitArray) -> Result(State, ProtocolError) {
  let parse_result =
    telnet.parse(bit_array.append(state.buffer, stream))
    |> result.replace_error(InputUnreadable)

  use telnet.Parsed(options:, lines:, buffer:) <- result.try(parse_result)
  use <- bool.guard(
    bit_array.byte_size(buffer) > max_input_buffer_size,
    Error(InputBufferOverflow),
  )

  let subnegotiations =
    list.filter_map(options, fn(x) {
      case x {
        telnet.Sub(subnegotiation) -> Ok(subnegotiation)
        _ -> Error(Nil)
      }
    })

  list.fold(lines, State(..state, buffer: buffer), fn(acc, line) {
    acc
    |> handle_options(options)
    |> handle_subnegotiations(subnegotiations)
    |> tap(fn(state) { handle_text(state.endpoint, line) })
  })
  |> Ok
}

fn handle_text(endpoint: Subject(CharacterMessage), string: String) -> Nil {
  use <- bool.guard(string == "", Nil)
  process.send(endpoint, event.UserSentCommand(string))
}

fn handle_options(state: State, options: List(telnet.TelnetCommand)) -> State {
  let options =
    list.fold(options, state.options, fn(acc, command) {
      case command {
        Do(byte) if byte == sga -> set_option(sga, acc, set.insert)
        Do(byte) if byte == echo_option ->
          set_option(echo_option, acc, set.insert)

        Dont(byte) | Wont(byte) -> set_option(byte, acc, set.delete)
        Will(byte) -> consider_option(byte, acc)
        _ -> acc
      }
    })

  State(..state, options: options)
}

fn handle_subnegotiations(
  state: State,
  subnegotiations: List(telnet.Subnegotiation),
) -> State {
  list.fold(subnegotiations, state, fn(acc, x) {
    case x {
      telnet.Naws(width: x, height: y) if x < 20 || y < 10 ->
        // if window size is too small or 0, assume Unknown
        State(..acc, window_size: Unknown)

      telnet.Naws(width:, height:) -> {
        let window_info = WindowSize(width: width, height: height)
        case state.window_size != window_info {
          True -> State(..acc, window_size: window_info)
          False -> acc
        }
      }
    }
  })
}

fn set_option(
  byte: Int,
  options: Set(TelnetOption),
  callback: fn(Set(TelnetOption), TelnetOption) -> Set(TelnetOption),
) -> Set(TelnetOption) {
  case byte_to_option(byte) {
    Ok(parsed_option) -> callback(options, parsed_option)
    Error(_) -> options
  }
}

fn consider_option(_byte: Int, options: Set(TelnetOption)) -> Set(TelnetOption) {
  options
}

fn byte_to_option(byte: Int) -> Result(TelnetOption, Nil) {
  case byte {
    x if x == eor_option -> Ok(EOR)
    _ -> Error(Nil)
  }
}

fn push_text(state: State, outputs: List(output.Text)) -> State {
  let conn = state.conn
  let outputs =
    list.map(
      outputs,
      output.map(_, [
        output.expand_newline,
        output.expand_colors_16,
        output.expand_colors_256,
      ]),
    )

  let newline =
    list.fold(outputs, state.newline, fn(newline, output) {
      let text = case newline {
        True -> string_tree.prepend(output.text, "\r\n")
        False -> output.text
      }

      text
      |> bytes_tree.from_string_tree()
      |> push(conn, _)

      output.newline
    })

  let end_transmission = case set.contains(state.options, EOR) {
    True -> <<iac, eor_command>> |> bytes_tree.from_bit_array()
    False -> <<iac, ga>> |> bytes_tree.from_bit_array()
  }

  push(conn, end_transmission)

  State(..state, newline: newline)
}

fn push(conn: glisten.Connection(a), data: BytesTree) -> Nil {
  glisten.send(conn, data)
  |> result.unwrap(Nil)
}

// terminate connection, self, and character
fn shutdown(
  conn: glisten.Connection(character.Outgoing),
) -> glisten.Next(State, glisten.Message(character.Outgoing)) {
  let _ = tcp.close(conn.socket)
  glisten.stop()
}

fn log_error(reason: String, ip_address: String) -> Nil {
  let string =
    "Connection < "
    <> ip_address
    <> " > encountered error: "
    <> reason
    <> ". Terminating connection."

  logging.log(logging.Error, string)
}
