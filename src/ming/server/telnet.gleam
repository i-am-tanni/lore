//// A library for parsing telnet streams.
//// 
//// Original Copyright (c) 2019 Eric Oestrich: 
//// [[Source]](https://github.com/oestrich/telnet-elixir)
//// [[MIT License]](https://github.com/oestrich/telnet-elixir?tab=MIT-1-ov-file#readme)
//// 
//// Ported to Gleam and modified.
//// 

import gleam/bit_array
import gleam/bool
import gleam/bytes_tree.{type BytesTree}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

/// Types that can be parsed out of a telnet stream. Anything which is not
/// text is considered out-of-band.
/// 
pub type TelnetCommand {
  /// Offer a telnet option
  /// 
  Will(Int)
  /// Communicate a telnet option is not available
  /// 
  Wont(Int)
  /// Request a telnet option
  /// 
  Do(Int)
  /// Decline a telnet option
  /// 
  Dont(Int)
  /// Send a command with no effect
  /// 
  NoOperation
  /// Text provided in-band
  /// 
  Text(String)
  /// Unknown option received
  /// 
  Unknown
  /// Subnegotiation
  /// 
  Sub(Subnegotiation)
}

pub type Subnegotiation {
  /// Negotiate About Window Size
  /// 
  Naws(width: Int, height: Int)
}

pub type ParseError {
  // Telnet stream could not be parsed
  //
  ParseError
  // Expected IAC SE to end sub-negotiation, but stream ended before it was
  // found. Likely in a forthcoming packet.
  //
  SubNegotiationEndNotFound
}

// interpret as command: marks beginning of out-of-band data
const iac = 255

// subnegotiation begin: mark sending or receiving subnegotiation out-of-band 
// (non-text) data
const sb = 250

// subnegotiation end: marks subnegotiation is over
const se = 240

// will communicates an option is available
const will = 251

// wont communicates an option is unavailable
const wont = 252

// do requests an option
const do = 253

// dont requests an option to be refused
const dont = 254

// No-operation(nop) is sometimes used to keep a connection alive without
// transmitting data
const nop = 241

// NAWS - Negotiate about window size
const naws = 31

/// Capture any text and completed telnet commands. Stash any incompleted
/// telnet commands that may be split between separate packets, then
/// buffer and prepend any split information to the next packet received.
/// 
pub fn parse(
  stream: BitArray,
) -> Result(#(List(TelnetCommand), String, BitArray), ParseError) {
  use #(parsed, leftover) <- result.try(parse_loop(stream, None, [], stream))

  let #(text, options) =
    parsed
    |> list.reverse
    |> list.filter_map(to_command)
    |> list.partition(is_text)

  let strings =
    text
    |> list.map(command_to_string)
    |> string.concat

  let buffer = case leftover {
    // if the buffer contains an incomplete IAC command, continue
    <<x>> | <<x, _:bits>> if x == iac -> leftover
    // else discard
    _ -> <<>>
  }

  Ok(#(options, strings, buffer))
}

fn parse_loop(
  stream: BitArray,
  current: Option(BytesTree),
  stack: List(BitArray),
  leftover: BitArray,
) -> Result(#(List(BitArray), BitArray), ParseError) {
  case stream {
    <<>> -> Ok(#(push(stack, <<>>, current), leftover))
    // capture any completed IACs and push any current data to the stack
    <<a, b, byte:size(8), data:bits>> if a == iac && b == will -> {
      // IAC WILL
      parse_loop(data, None, push(stack, <<will, byte>>, current), data)
    }
    <<a, b, byte:size(8), data:bits>> if a == iac && b == wont -> {
      // IAC WONT
      parse_loop(data, None, push(stack, <<wont, byte>>, current), data)
    }
    <<a, b, byte:size(8), data:bits>> if a == iac && b == do -> {
      // IAC DO
      parse_loop(data, None, push(stack, <<do, byte>>, current), data)
    }
    <<a, b, byte:size(8), data:bits>> if a == iac && b == dont -> {
      // IAC DONT
      parse_loop(data, None, push(stack, <<dont, byte>>, current), data)
    }
    <<a, b, data:bits>> if a == iac && b == sb -> {
      // IAC SB
      case parse_sub_negotiation(data, bytes_tree.from_bit_array(<<sb>>)) {
        Ok(#(sub, data)) ->
          parse_loop(data, None, push(stack, sub, current), data)
        Error(SubNegotiationEndNotFound) ->
          Ok(#(push(stack, <<>>, current), leftover))
        Error(ParseError) -> Error(ParseError)
      }
    }
    <<a, b, data:bits>> if a == iac && b == nop -> {
      // IAC NOP
      parse_loop(data, None, push(stack, <<nop>>, current), data)
    }
    // else if IAC started but not completed, start a new current capture
    <<a, data:bits>> if a == iac -> {
      parse_loop(
        data,
        Some(bytes_tree.from_bit_array(<<iac>>)),
        push(stack, <<>>, current),
        stream,
      )
    }

    // ...else capture in current until an IAC is encountered
    <<byte:size(8), data:bits>> -> {
      let current = case current {
        Some(current) -> bytes_tree.append(current, <<byte>>)
        None -> bytes_tree.from_bit_array(<<byte>>)
      }
      parse_loop(data, Some(current), stack, leftover)
    }
    _ -> Error(ParseError)
  }
}

// The accumulator is a stack that gets pre-pended and reversed at the very end
// of the loop. This function ensures that only data gets pushed onto the stack,
// and that there are no empty elements.
//
fn push(
  stack: List(BitArray),
  iac_bits: BitArray,
  current: Option(BytesTree),
) -> List(BitArray) {
  case current, iac_bits {
    // only push data to the stack
    Some(a), <<>> -> [bytes_tree.to_bit_array(a), ..stack]
    Some(a), b -> [bytes_tree.to_bit_array(a), b, ..stack]
    None, <<>> -> stack
    None, b -> [b, ..stack]
  }
}

// Subnegotiation is used for procotols like GMCP / MXP / MSSP, etc.
//
fn parse_sub_negotiation(
  stream: BitArray,
  stack: BytesTree,
) -> Result(#(BitArray, BitArray), ParseError) {
  case stream {
    <<>> -> Error(SubNegotiationEndNotFound)
    <<a, b, rest:bits>> if a == iac && b == se -> {
      let subnegotiation = bytes_tree.to_bit_array(stack)
      Ok(#(subnegotiation, rest))
    }
    <<byte:size(8), data:bits>> ->
      parse_sub_negotiation(data, bytes_tree.append(stack, <<byte>>))
    _ -> Error(ParseError)
  }
}

fn to_command(element: BitArray) -> Result(TelnetCommand, TelnetCommand) {
  let command = case element {
    <<x, byte>> if x == will -> Will(byte)
    <<x, byte>> if x == wont -> Wont(byte)
    <<x, byte>> if x == do -> Do(byte)
    <<x, byte>> if x == dont -> Dont(byte)
    <<x, data:bits>> if x == sb -> to_subnegotiation(data)
    <<x>> if x == nop -> NoOperation
    <<x, _:bits>> | <<x>> if x == iac -> Unknown
    binary ->
      case bit_array.to_string(binary) {
        Ok(string) -> Text(string)
        Error(_) -> Unknown
      }
  }
  // transform to a result where an Unknown is an error
  use <- bool.guard(command == Unknown, Error(Unknown))
  Ok(command)
}

fn to_subnegotiation(data: BitArray) -> TelnetCommand {
  case data {
    <<x, width:16, height:16>> if x == naws ->
      Sub(Naws(width: width, height: height))

    _ -> Unknown
  }
}

fn is_text(x: TelnetCommand) -> Bool {
  case x {
    Text(_) -> True
    _ -> False
  }
}

fn command_to_string(x: TelnetCommand) -> String {
  // we will only ever call this on Text
  let assert Text(string) = x
  string
}
