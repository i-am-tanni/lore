//// A library for parsing telnet streams.
//// 
//// Original Copyright (c) 2019 Eric Oestrich: 
//// [[Source]](https://github.com/oestrich/telnet-elixir)
//// [[MIT License]](https://github.com/oestrich/telnet-elixir?tab=MIT-1-ov-file#readme)
//// 
//// Ported to Gleam and modified.
//// 
//// TCP is a byte stream protocol. We could receive a single character or
//// multiple lines of text. In addition, we have out of band information
//// that can be communicated via an IAC byte.
//// 

import gleam/bit_array
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
  Text(BitArray)
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

/// Output returned by the parser result. Buffer is any incomplete data to be 
/// prepended to the next packet.
/// 
pub type Parsed {
  Parsed(options: List(TelnetCommand), lines: List(String), buffer: BitArray)
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

const ascii_lf = 10

const ascii_cr = 13

const ascii_us = 31

const ascii_del = 127

/// Capture any text and completed telnet commands. Stash any incompleted
/// telnet commands that may be split between separate packets, then
/// buffer and prepend any split information to the next packet received.
/// 
pub fn parse(stream: BitArray) -> Result(Parsed, ParseError) {
  use #(parsed, leftover) <- result.try(parse_loop(stream, None, [], stream))

  let #(text, options) =
    parsed
    |> list.filter_map(to_command)
    |> list.partition(is_text)

  let #(lines, fragment) =
    text
    |> list.map(fn(text) {
      let assert Text(bit_array) = text
      bit_array
    })
    // No need to reverse since we get that for free when we partition
    |> partition_lines

  let buffer = case leftover {
    // if the buffer contains an incomplete IAC command, continue
    <<x, _:bits>> if x == iac -> leftover
    // else default to any text fragment received.
    // These should be mutually exclusive outcomes!
    _ -> fragment
  }

  Ok(Parsed(list.reverse(options), lines, buffer))
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
    <<a, b, byte:size(8), data:bits>> if a == iac && b == will ->
      // IAC WILL
      parse_loop(data, None, push(stack, <<will, byte>>, current), data)

    <<a, b, byte:size(8), data:bits>> if a == iac && b == wont ->
      // IAC WONT
      parse_loop(data, None, push(stack, <<wont, byte>>, current), data)

    <<a, b, byte:size(8), data:bits>> if a == iac && b == do ->
      // IAC DO
      parse_loop(data, None, push(stack, <<do, byte>>, current), data)

    <<a, b, byte:size(8), data:bits>> if a == iac && b == dont ->
      // IAC DONT
      parse_loop(data, None, push(stack, <<dont, byte>>, current), data)

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

    // else if IAC started but not completed, start a new capture
    <<a, data:bits>> if a == iac ->
      parse_loop(
        data,
        Some(bytes_tree.from_bit_array(<<iac>>)),
        push(stack, <<>>, current),
        stream,
      )

    <<"\r\n", data:bits>> ->
      parse_loop(data, None, push(stack, <<ascii_cr, ascii_lf>>, current), data)

    // filter out ascii control characters EXCEPT for LF and CR
    <<x, data:bits>> if x <= ascii_us || x == ascii_del ->
      parse_loop(data, current, stack, leftover)

    // ...else capture until an IAC is encountered
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
    Some(a), b -> [b, bytes_tree.to_bit_array(a), ..stack]
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
    binary -> Text(binary)
  }
  // transform to a result where an Unknown is an error
  case command != Unknown {
    True -> Ok(command)
    False -> Error(Unknown)
  }
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

// Returns a pair with a list of full lines as string and any incomplete lines
// as a bitarray.
// Warning! Reverses the list which is intended behavior.
// 
fn partition_lines(text: List(BitArray)) -> #(List(String), BitArray) {
  partition_lines_loop(
    text,
    accumulating: [],
    found: [],
    incomplete: [],
    is_in_line: False,
  )
}

fn partition_lines_loop(
  text text: List(BitArray),
  accumulating current: List(BitArray),
  found lines: List(String),
  incomplete leftover: List(BitArray),
  is_in_line in_line: Bool,
) -> #(List(String), BitArray) {
  case text {
    [] if in_line -> {
      let current =
        current
        |> list.filter_map(bit_array.to_string)
        |> string.concat

      let leftover = bit_array.concat(leftover)

      #([current, ..lines], leftover)
    }

    [] -> {
      let leftover = bit_array.concat(leftover)
      #(lines, leftover)
    }

    [next, ..rest] ->
      case has_newline(next) {
        // Already in a line and a newline found
        True if in_line -> {
          let current =
            current
            |> list.filter_map(bit_array.to_string)
            |> string.concat

          partition_lines_loop(
            rest,
            accumulating: [next],
            found: [current, ..lines],
            incomplete: leftover,
            is_in_line: True,
          )
        }

        // Not in a line and newline found
        True ->
          partition_lines_loop(
            rest,
            accumulating: [next],
            found: lines,
            incomplete: leftover,
            is_in_line: True,
          )

        // In a line, but newline not found -- keep accumulating
        False if in_line ->
          partition_lines_loop(
            rest,
            accumulating: [next, ..current],
            found: lines,
            incomplete: leftover,
            is_in_line: True,
          )

        // In a fragment. No newlines found.
        False ->
          partition_lines_loop(
            rest,
            accumulating: current,
            found: lines,
            incomplete: [next, ..leftover],
            is_in_line: False,
          )
      }
  }
}

fn has_newline(text: BitArray) -> Bool {
  case text {
    <<>> -> False
    <<"\r\n", _:bits>> | <<"\n", _:bits>> | <<"\n\r", _:bits>> -> True
    <<_:size(8), rest:bits>> -> has_newline(rest)
    _ -> False
  }
}
