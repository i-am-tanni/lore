//// Transforms outgoing text output, replacing color codes to ansi, 
//// expanding newlines into "\r\n", etc.
//// 

import gleam/bit_array
import gleam/bytes_tree.{type BytesTree}
import gleam/list
import gleam/result
import gleam/string_tree.{type StringTree}

// ascii char '0'
const char0 = 48

// ascii char '9'
const char9 = 57

/// Text to be sent to user over the wire
/// 
pub type Text {
  /// The newline bool communicates to the protocol to prepend a newline
  /// to the following output.
  /// 
  Text(text: StringTree, newline: Bool)
}

/// Map over Text with a list of BitArray transformers
/// 
pub fn map(
  output: Text,
  output_processors: List(fn(BitArray) -> BitArray),
) -> Text {
  let text =
    string_tree_map(output.text, fn(binary) {
      // for each processor, transform the binary
      list.fold(output_processors, binary, fn(acc, processor) { processor(acc) })
    })

  Text(..output, text: text)
}

//
// Output Processors
//

/// Expand any newlines to '\r\n'.
/// This avoids having to remember the order and avoids mistakes where \r is
/// omitted.
/// 
pub fn expand_newline(binary: BitArray) -> BitArray {
  let result =
    expand_newline_loop(binary, found: False, accumulating: bytes_tree.new())

  case result {
    Ok(update) -> bytes_tree.to_bit_array(update)
    Error(_no_change) -> binary
  }
}

fn expand_newline_loop(
  binary: BitArray,
  found is_found: Bool,
  accumulating acc: BytesTree,
) -> Result(BytesTree, Nil) {
  case binary {
    <<>> if is_found -> Ok(acc)
    <<>> -> Error(Nil)
    <<"\n", rest:bits>> ->
      expand_newline_loop(rest, True, bytes_tree.append(acc, <<"\r\n">>))
    <<x:8, rest:bits>> ->
      expand_newline_loop(rest, is_found, bytes_tree.append(acc, <<x>>))
    _ -> Error(Nil)
  }
}

pub fn expand_colors_16(binary: BitArray) -> BitArray {
  let result =
    expand_colors_16_loop(binary, found: False, accumulating: bytes_tree.new())

  case result {
    Ok(update) -> bytes_tree.to_bit_array(update)
    Error(_no_change) -> binary
  }
}

/// Expands 16 colors. & indicates foreground. { indicates background.
/// 0; is reset.
/// 
/// Codes:
/// - x - black
/// - r - red
/// - g - green
/// - O - brown / orange
/// - b - blue
/// - p - purple
/// - c - cyan
/// - w - white
/// - z - grey
/// - R - bright red
/// - G - bright green
/// - Y - yellow
/// - B - bright blue
/// - P - bright pink
/// - C - bright cyan
/// - W - bright white
/// 
fn expand_colors_16_loop(
  binary: BitArray,
  found is_found: Bool,
  accumulating acc: BytesTree,
) -> Result(BytesTree, Nil) {
  case binary {
    <<>> if is_found -> Ok(acc)
    <<>> -> Error(Nil)
    // foreground black
    <<"&x", rest:bits>> ->
      expand_colors_16_loop(
        rest,
        True,
        bytes_tree.append_string(acc, "\u{1b}[30m"),
      )
    // foreground red
    <<"&r", rest:bits>> ->
      expand_colors_16_loop(
        rest,
        True,
        bytes_tree.append_string(acc, "\u{1b}[31m"),
      )
    // foreground green
    <<"&g", rest:bits>> ->
      expand_colors_16_loop(
        rest,
        True,
        bytes_tree.append_string(acc, "\u{1b}[32m"),
      )
    // foreground yellow
    <<"&O", rest:bits>> ->
      expand_colors_16_loop(
        rest,
        True,
        bytes_tree.append_string(acc, "\u{1b}[33m"),
      )
    // foreground blue
    <<"&b", rest:bits>> ->
      expand_colors_16_loop(
        rest,
        True,
        bytes_tree.append_string(acc, "\u{1b}[34m"),
      )
    // foreground magenta
    <<"&p", rest:bits>> ->
      expand_colors_16_loop(
        rest,
        True,
        bytes_tree.append_string(acc, "\u{1b}[35m"),
      )
    // foreground cyan
    <<"&c", rest:bits>> ->
      expand_colors_16_loop(
        rest,
        True,
        bytes_tree.append_string(acc, "\u{1b}[36m"),
      )
    // foreground white
    <<"&w", rest:bits>> ->
      expand_colors_16_loop(
        rest,
        True,
        bytes_tree.append_string(acc, "\u{1b}[37m"),
      )
    // foreground grey
    <<"&z", rest:bits>> ->
      expand_colors_16_loop(
        rest,
        True,
        bytes_tree.append_string(acc, "\u{1b}[90m"),
      )
    // foreground bright red
    <<"&R", rest:bits>> ->
      expand_colors_16_loop(
        rest,
        True,
        bytes_tree.append_string(acc, "\u{1b}[91m"),
      )
    // foreground bright green
    <<"&G", rest:bits>> ->
      expand_colors_16_loop(
        rest,
        True,
        bytes_tree.append_string(acc, "\u{1b}[92m"),
      )
    // foreground bright yellow
    <<"&Y", rest:bits>> ->
      expand_colors_16_loop(
        rest,
        True,
        bytes_tree.append_string(acc, "\u{1b}[93m"),
      )
    // foreground bright blue
    <<"&B", rest:bits>> ->
      expand_colors_16_loop(
        rest,
        True,
        bytes_tree.append_string(acc, "\u{1b}[94m"),
      )
    // foreground bright pink
    <<"&P", rest:bits>> ->
      expand_colors_16_loop(
        rest,
        True,
        bytes_tree.append_string(acc, "\u{1b}[95m"),
      )
    // foreground bright cyan
    <<"&C", rest:bits>> ->
      expand_colors_16_loop(
        rest,
        True,
        bytes_tree.append_string(acc, "\u{1b}[96m"),
      )
    // foreground bright white
    <<"&W", rest:bits>> ->
      expand_colors_16_loop(
        rest,
        True,
        bytes_tree.append_string(acc, "\u{1b}[97m"),
      )
    // background black
    <<"{x", rest:bits>> ->
      expand_colors_16_loop(
        rest,
        True,
        bytes_tree.append_string(acc, "\u{1b}[40m"),
      )
    // background red
    <<"{r", rest:bits>> ->
      expand_colors_16_loop(
        rest,
        True,
        bytes_tree.append_string(acc, "\u{1b}[41m"),
      )
    // background green
    <<"{g", rest:bits>> ->
      expand_colors_16_loop(
        rest,
        True,
        bytes_tree.append_string(acc, "\u{1b}[42m"),
      )
    // background orange
    <<"{O", rest:bits>> ->
      expand_colors_16_loop(
        rest,
        True,
        bytes_tree.append_string(acc, "\u{1b}[43m"),
      )
    // background blue
    <<"{b", rest:bits>> ->
      expand_colors_16_loop(
        rest,
        True,
        bytes_tree.append_string(acc, "\u{1b}[44m"),
      )
    // background purple
    <<"{p", rest:bits>> ->
      expand_colors_16_loop(
        rest,
        True,
        bytes_tree.append_string(acc, "\u{1b}[45m"),
      )
    // background cyan
    <<"{c", rest:bits>> ->
      expand_colors_16_loop(
        rest,
        True,
        bytes_tree.append_string(acc, "\u{1b}[46m"),
      )
    // background white
    <<"{w", rest:bits>> ->
      expand_colors_16_loop(
        rest,
        True,
        bytes_tree.append_string(acc, "\u{1b}[47m"),
      )
    // background grey
    <<"{z", rest:bits>> ->
      expand_colors_16_loop(
        rest,
        True,
        bytes_tree.append_string(acc, "\u{1b}[100m"),
      )
    // background bright red
    <<"{R", rest:bits>> ->
      expand_colors_16_loop(
        rest,
        True,
        bytes_tree.append_string(acc, "\u{1b}[101m"),
      )
    // background bright green
    <<"{G", rest:bits>> ->
      expand_colors_16_loop(
        rest,
        True,
        bytes_tree.append_string(acc, "\u{1b}[102m"),
      )
    // background bright yellow
    <<"{Y", rest:bits>> ->
      expand_colors_16_loop(
        rest,
        True,
        bytes_tree.append_string(acc, "\u{1b}[103m"),
      )
    // background bright blue
    <<"{B", rest:bits>> ->
      expand_colors_16_loop(
        rest,
        True,
        bytes_tree.append_string(acc, "\u{1b}[104m"),
      )
    // background bright pink
    <<"{P", rest:bits>> ->
      expand_colors_16_loop(
        rest,
        True,
        bytes_tree.append_string(acc, "\u{1b}[105m"),
      )
    // background bright cyan
    <<"{C", rest:bits>> ->
      expand_colors_16_loop(
        rest,
        True,
        bytes_tree.append_string(acc, "\u{1b}[106m"),
      )
    // background bright white
    <<"{W", rest:bits>> ->
      expand_colors_16_loop(
        rest,
        True,
        bytes_tree.append_string(acc, "\u{1b}[107m"),
      )
    // color reset
    <<"0;", rest:bits>> ->
      expand_colors_16_loop(
        rest,
        True,
        bytes_tree.append_string(acc, "\u{1b}[0m"),
      )
    <<x:size(8), rest:bits>> ->
      expand_colors_16_loop(rest, is_found, bytes_tree.append(acc, <<x>>))
    _ -> Error(Nil)
  }
}

/// &000 == foreground color. {000 == background color. 0; is reset.
/// 
pub fn expand_colors_256(binary: BitArray) -> BitArray {
  let result =
    expand_colors_256_loop(binary, found: False, accumulating: bytes_tree.new())

  case result {
    Ok(update) -> bytes_tree.to_bit_array(update)
    Error(_no_change) -> binary
  }
}

fn expand_colors_256_loop(
  binary: BitArray,
  found is_found: Bool,
  accumulating acc: BytesTree,
) -> Result(BytesTree, Nil) {
  case binary {
    <<>> if is_found -> Ok(acc)
    <<>> -> Error(Nil)

    // avoid messing up existing color escape sequences
    <<"\u{1b}[", rest:bits>> ->
      expand_colors_256_loop(
        rest,
        True,
        bytes_tree.append_string(acc, "\u{1b}["),
      )

    <<"&", a, b, c, rest:bits>>
      if a >= char0
      && a <= char9
      && b >= char0
      && b <= char9
      && c >= char0
      && c <= char9
    -> {
      use code <- result.try(bit_array.to_string(<<a, b, c>>))
      expand_colors_256_loop(
        rest,
        True,
        bytes_tree.append_string(acc, "\u{1b}[38;5;" <> code <> "m"),
      )
    }

    <<"&", a, b, rest:bits>>
      if a >= char0 && a <= char9 && b >= char0 && b <= char9
    -> {
      use code <- result.try(bit_array.to_string(<<a, b>>))
      expand_colors_256_loop(
        rest,
        True,
        bytes_tree.append_string(acc, "\u{1b}[38;5;" <> code <> "m"),
      )
    }

    <<"&", a, rest:bits>> if a >= char0 && a <= char9 -> {
      use code <- result.try(bit_array.to_string(<<a>>))
      expand_colors_256_loop(
        rest,
        True,
        bytes_tree.append_string(acc, "\u{1b}[38;5;" <> code <> "m"),
      )
    }

    <<"{", a, b, c, rest:bits>>
      if a >= char0
      && a <= char9
      && b >= char0
      && b <= char9
      && c >= char0
      && c <= char9
    -> {
      use code <- result.try(bit_array.to_string(<<a, b, c>>))
      expand_colors_256_loop(
        rest,
        True,
        bytes_tree.append_string(acc, "\u{1b}[48;5;" <> code <> "m"),
      )
    }

    <<"{", a, b, rest:bits>>
      if a >= char0 && a <= char9 && b >= char0 && b <= char9
    -> {
      use code <- result.try(bit_array.to_string(<<a, b>>))
      expand_colors_256_loop(
        rest,
        True,
        bytes_tree.append_string(acc, "\u{1b}[48;5;" <> code <> "m"),
      )
    }

    <<"{", a, rest:bits>> if a >= char0 && a <= char9 -> {
      use code <- result.try(bit_array.to_string(<<a>>))
      expand_colors_256_loop(
        rest,
        True,
        bytes_tree.append_string(acc, "\u{1b}[48;5;" <> code <> "m"),
      )
    }

    <<"0;", rest:bits>> ->
      expand_colors_256_loop(
        rest,
        True,
        bytes_tree.append_string(acc, "\u{1b}[0m"),
      )

    <<x:size(8), rest:bits>> ->
      expand_colors_256_loop(rest, is_found, bytes_tree.append(acc, <<x>>))
    _ -> Error(Nil)
  }
}

/// Avoid replacing escape sequences
/// Like `list.map` but works on a StringTree.
/// 
@external(erlang, "lore_ffi", "iolist_map")
fn string_tree_map(
  over tree: StringTree,
  with fun: fn(BitArray) -> BitArray,
) -> StringTree
