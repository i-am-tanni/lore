//// Processes outgoing text output, replacing color codes, etc.
//// 

import gleam/bytes_tree.{type BytesTree}
import gleam/list
import gleam/string_tree.{type StringTree}

/// Text to be sent to user over the wire
/// 
pub type Text {
  /// The newline bool communicates to the protocol to prepend a newline
  /// to the following output.
  /// 
  Text(text: StringTree, newline: Bool)
}

/// Outgoing messages from the character to the I/O process.
/// 
pub type Outgoing {
  /// A transmission to be pushed to the socket
  PushText(List(Text))
  /// signal to terminate connection
  Halt
}

/// Map over a StringTree with a list of BitArray transformers
/// 
pub fn map_output(
  tree: StringTree,
  output_processors: List(fn(BitArray) -> BitArray),
) -> StringTree {
  string_tree_map(tree, fn(binary) {
    // for each processor, transform the binary
    list.fold(output_processors, binary, fn(acc, processor) { processor(acc) })
  })
}

//
// Output Processors
//

/// Expand any newlines to '\r\n'.
/// This avoids having to remember the order and simplifies the cognitive load
/// of having to remember to add the \r.
/// 
pub fn expand_newline(binary: BitArray) -> BitArray {
  let found =
    expand_newline_loop(binary, found: False, accumulator: bytes_tree.new())

  case found {
    Ok(update) -> bytes_tree.to_bit_array(update)
    Error(_no_change) -> binary
  }
}

fn expand_newline_loop(
  binary: BitArray,
  found is_found: Bool,
  accumulator acc: BytesTree,
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

/// Maps over a StringTree and transforms any BitArrays found with the given 
/// fun. This is useful for output processing.
/// 
@external(erlang, "helpers", "iolist_map")
fn string_tree_map(
  over tree: StringTree,
  with fun: fn(BitArray) -> BitArray,
) -> StringTree

/// Maps and folders over a StringTree. This is useful for output processing.
/// 
@external(erlang, "helpers", "iolist_map_fold")
fn string_tree_map_fold(
  over tree: StringTree,
  from initial: a,
  with fun: fn(a, BitArray) -> #(a, BitArray),
) -> #(a, StringTree)
