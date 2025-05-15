import gleam/bit_array
import gleam/list
import gleam/string
import gleam/string_tree.{type StringTree}
import hyphenation
import hyphenation/language

/// A wrapper type for different types of string output renders.
/// - Leaf - wraps a single string
/// - Leaves - wraps a list of strings
/// - Tree - wraps a StringTree
/// 
pub type View {
  /// A single string.
  Leaf(String)
  /// A list of strings.
  Leaves(List(String))
  /// A list of nested string lists.
  Tree(StringTree)
}

/// Converts a View to a StringTree
/// 
pub fn to_string_tree(view: View) -> StringTree {
  case view {
    Leaf(string) -> string_tree.from_string(string)
    Leaves(strings) -> string_tree.from_strings(strings)
    Tree(tree) -> tree
  }
}

/// Splits a string into a list of strings where each string in the list
/// will not exceed the given line length and no words are broken up.
/// 
pub fn word_wrap(s: String, line_length: Int) -> List(String) {
  word_wrap_loop(
    process: bit_array.from_string(s),
    accumulate: [],
    track: [],
    and: [],
    with: 0,
    not_to_exceed: line_length,
  )
}

fn word_wrap_loop(
  process text: BitArray,
  accumulate acc: List(List(String)),
  track curr_line: List(String),
  and curr_word: List(UtfCodepoint),
  with grapheme_count: Int,
  not_to_exceed line_length: Int,
) -> List(String) {
  case text, acc, curr_line, curr_word {
    // if there is no more text to process, migrates any remaining framgments 
    // to the current / next line and returns the accumulator
    <<>>, lines, [], [] ->
      lines
      |> list.reverse
      |> list.map(string.join(_, " "))

    <<>>, lines, curr_line, [] ->
      word_wrap_loop(
        process: <<>>,
        accumulate: [list.reverse(curr_line), ..lines],
        track: [],
        and: [],
        with: grapheme_count,
        not_to_exceed: line_length,
      )

    <<>>, lines, curr_line, curr_word ->
      // Since there's nothing left to process, push the current word to the 
      // stack.
      //
      push_word(<<>>, lines, curr_line, curr_word, grapheme_count, line_length)

    <<" ", rest:bits>>, _, _, [] ->
      // if multiples of white space are encountered, ignore
      word_wrap_loop(
        process: rest,
        accumulate: acc,
        track: curr_line,
        and: [],
        with: grapheme_count,
        not_to_exceed: line_length,
      )

    <<" ", rest:bits>>, lines, curr_line, curr_word ->
      // If space is encounted, the current word is complete. Push onto the 
      // stack.
      push_word(rest, lines, curr_line, curr_word, grapheme_count, line_length)

    <<cp:utf8_codepoint, rest:bits>>, lines, curr_line, curr_word -> {
      // By default, simply build up the next word unless a space is encountered
      word_wrap_loop(
        process: rest,
        accumulate: lines,
        track: curr_line,
        and: [cp, ..curr_word],
        with: grapheme_count,
        not_to_exceed: line_length,
      )
    }

    _, _, _, _ -> panic as "Impossible"
  }
}

// Pushes a word onto the current line as long as it fits.
// If it doesn't fit, attempt a hyphenation and push the remainder onto a new
// line.
// ..else, push the current line to the accumulator and start a new line with 
// the given word.
//
fn push_word(
  process rest: BitArray,
  accumulate lines: List(List(String)),
  track curr_line: List(String),
  and word: List(UtfCodepoint),
  with grapheme_count: Int,
  not_to_exceed line_length: Int,
) -> List(String) {
  let word = list.reverse(word) |> string.from_utf_codepoints()
  let word_length = string.length(word)

  let #(acc, curr_line, grapheme_count) = case
    grapheme_count + word_length >= line_length
  {
    True -> {
      // if the line_length is exceeded, attempt to hyphenate
      case hyphenate(word, with: grapheme_count, not_to_exceed: line_length) {
        // if a hyphenation is possible, push the hyphenated segement to the
        // current line, and then push that line to the accumulator. Then 
        // start a new line with the remainding word fragment.
        Ok(#(take, remainder)) -> {
          let line = list.reverse([take, ..curr_line])
          #([line, ..lines], [remainder], string.length(remainder))
        }
        Error(word) -> {
          // else if hyphenation is not possible, fallback to simple word wrap
          let line = list.reverse(curr_line)
          #([line, ..lines], [word], string.length(word))
        }
      }
    }
    // ..else if word fits on the current line
    False -> #(lines, [word, ..curr_line], word_length + grapheme_count)
  }

  word_wrap_loop(
    process: rest,
    accumulate: acc,
    track: curr_line,
    and: [],
    // + 1 is added to the count to account for white space
    with: grapheme_count + 1,
    not_to_exceed: line_length,
  )
}

// Returns a result of the hyphenation attempt: a tuple pair where the first
// element is the hyphenated word and the second is the remainder.
// If no hyphenation can be performed, returns the given unhyphenated word.
//
fn hyphenate(
  word: String,
  with grapheme_count: Int,
  not_to_exceed line_length: Int,
) -> Result(#(String, String), String) {
  let hyphenator = hyphenation.hyphenator(language.EnglishUS)
  case hyphenation.hyphenate(word, hyphenator) {
    [_no_hyphenations_available] -> Error(word)
    hyphenations ->
      hyphenate_loop(
        hyphenations,
        context: word,
        accumulate: [],
        with: grapheme_count,
        not_to_exceed: line_length,
      )
  }
}

// Keep adding the hyphenation chunks until max fit is achieved.
//
fn hyphenate_loop(
  hyphenations: List(String),
  context word: String,
  accumulate acc: List(String),
  with grapheme_count: Int,
  not_to_exceed line_length: Int,
) -> Result(#(String, String), String) {
  case hyphenations {
    [first, ..rest] -> {
      let length = string.length(first)
      let grapheme_count = grapheme_count + length

      case grapheme_count >= line_length {
        True if acc == [] ->
          // no hyphenations fit
          Error(word)

        True -> {
          // if max fit is achieved, return hyphenated segment and remainder
          let take = list.reverse(["-", ..acc]) |> string.concat()
          let remainder = string.concat(hyphenations)
          Ok(#(take, remainder))
        }

        False ->
          // ..else keep adding until max fit is achieved
          hyphenate_loop(
            rest,
            context: word,
            accumulate: [first, ..acc],
            with: grapheme_count,
            not_to_exceed: line_length,
          )
      }
    }
    [] -> {
      // This should be impossible! We already checked that the full word
      // would not fit before calling `hyphenate()`. If the list was exhausted
      // then that implies that the full word DOES fit.
      //
      Error(word)
    }
  }
}
