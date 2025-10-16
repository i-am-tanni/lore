import gleam/bit_array
import gleam/bytes_tree.{type BytesTree}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import gleam/string_tree.{type StringTree}
import hyphenation
import hyphenation/language
import lore/character/pronoun
import lore/world

pub type PerspectiveSimple {
  Self
  Witness
}

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
  /// Placeholder for generating newlines
  Blank
}

/// Template varables:
/// - $n - Subject name
/// - $e - He / She pronouns
/// - $m - Him / Her pronouns
/// - $s - His / Her pronouns
/// - $mself - Himself / Herself pronouns
/// - $N - Victim name
/// - $E - Victim he / she
/// - $M - Victim him / her
/// - $S - Victim his / her 
/// - $MSELF - Victim himself, herself
/// 
pub type Report {
  ReportBasic(self: String, witness: String)
  ReportAdvanced(self: String, witness: String, victim: String)
}

pub fn render_report(
  occurance: Report,
  witness: world.MobileInternal,
  actor: world.Mobile,
  actee: Option(world.Mobile),
) -> View {
  let witness_id = witness.id
  case occurance, actee {
    // if no victim
    ReportBasic(..), _ | ReportAdvanced(..), None ->
      case witness_id {
        _ if witness_id == actor.id ->
          report_simple_stringify(occurance.self, actor)

        _ -> report_simple_stringify(occurance.witness, actor)
      }

    ReportAdvanced(victim:, self:, witness:), Some(actee) ->
      case witness_id {
        _ if witness_id == actee.id ->
          report_advanced_stringify(victim, actor, actee)

        _ if witness_id == actor.id ->
          report_advanced_stringify(self, actor, actee)

        _ -> report_advanced_stringify(witness, actor, actee)
      }
  }
  |> Leaf
}

fn report_simple_stringify(
  report_basic: String,
  subject: world.Mobile,
) -> String {
  let to_transform = bit_array.from_string(report_basic)
  case report_simple_loop(to_transform, subject, bytes_tree.new()) {
    Ok(string) -> string
    Error(Nil) -> ""
  }
}

fn report_simple_loop(
  report_basic: BitArray,
  subject: world.Mobile,
  acc: BytesTree,
) -> Result(String, Nil) {
  let pronouns = pronoun.lookup(subject.pronouns)
  case report_basic {
    <<>> ->
      acc
      |> bytes_tree.to_bit_array
      |> bit_array.to_string

    // subject name
    <<"$n", rest:bits>> ->
      report_simple_loop(
        rest,
        subject,
        bytes_tree.append_string(acc, subject.name),
      )

    // he / her type pronouns
    <<"$e", rest:bits>> ->
      report_simple_loop(
        rest,
        subject,
        bytes_tree.append_string(acc, pronouns.he),
      )

    // his / hers type pronouns
    <<"$s", rest:bits>> ->
      report_simple_loop(
        rest,
        subject,
        bytes_tree.append_string(acc, pronouns.his),
      )

    // him / hers type pronouns
    <<"$m", rest:bits>> ->
      report_simple_loop(
        rest,
        subject,
        bytes_tree.append_string(acc, pronouns.him),
      )

    // himself / herself type pronouns
    <<"$mself", rest:bits>> ->
      report_simple_loop(
        rest,
        subject,
        bytes_tree.append_string(acc, pronouns.himself),
      )

    <<x:8, rest:bits>> ->
      report_simple_loop(rest, subject, bytes_tree.append(acc, <<x>>))

    _ -> report_simple_loop(<<>>, subject, acc)
  }
}

fn report_advanced_stringify(
  report_advanced: String,
  subject: world.Mobile,
  victim: world.Mobile,
) -> String {
  let result =
    report_advanced_loop(
      bit_array.from_string(report_advanced),
      subject,
      victim,
      bytes_tree.new(),
    )

  case result {
    Ok(transformed) -> transformed
    Error(Nil) -> ""
  }
}

fn report_advanced_loop(
  report_advanced: BitArray,
  subject: world.Mobile,
  victim: world.Mobile,
  acc: BytesTree,
) -> Result(String, Nil) {
  let subject_pronouns = pronoun.lookup(subject.pronouns)
  let victim_pronouns = pronoun.lookup(subject.pronouns)

  case report_advanced {
    <<>> ->
      acc
      |> bytes_tree.to_bit_array
      |> bit_array.to_string

    <<"$n", rest:bits>> ->
      report_advanced_loop(
        rest,
        subject,
        victim,
        bytes_tree.append_string(acc, subject.name),
      )

    <<"$e", rest:bits>> ->
      report_advanced_loop(
        rest,
        subject,
        victim,
        bytes_tree.append_string(acc, subject_pronouns.he),
      )

    <<"$s", rest:bits>> ->
      report_advanced_loop(
        rest,
        subject,
        victim,
        bytes_tree.append_string(acc, subject_pronouns.his),
      )

    <<"$m", rest:bits>> ->
      report_advanced_loop(
        rest,
        subject,
        victim,
        bytes_tree.append_string(acc, subject_pronouns.him),
      )

    <<"$mself", rest:bits>> ->
      report_advanced_loop(
        rest,
        subject,
        victim,
        bytes_tree.append_string(acc, subject_pronouns.himself),
      )

    <<"$N", rest:bits>> ->
      report_advanced_loop(
        rest,
        subject,
        victim,
        bytes_tree.append_string(acc, victim.name),
      )

    <<"$E", rest:bits>> ->
      report_advanced_loop(
        rest,
        subject,
        victim,
        bytes_tree.append_string(acc, victim_pronouns.he),
      )

    <<"$S", rest:bits>> ->
      report_advanced_loop(
        rest,
        subject,
        victim,
        bytes_tree.append_string(acc, victim_pronouns.his),
      )

    <<"$M", rest:bits>> ->
      report_advanced_loop(
        rest,
        subject,
        victim,
        bytes_tree.append_string(acc, victim_pronouns.him),
      )

    <<"$MSELF", rest:bits>> ->
      report_advanced_loop(
        rest,
        subject,
        victim,
        bytes_tree.append_string(acc, victim_pronouns.himself),
      )

    <<x:8, rest:bits>> ->
      report_advanced_loop(rest, subject, victim, bytes_tree.append(acc, <<x>>))

    _ -> report_advanced_loop(<<>>, subject, victim, acc)
  }
}

/// Converts a View to a StringTree
/// 
pub fn to_string_tree(view: View) -> StringTree {
  case view {
    Leaf(string) -> string_tree.from_string(string)
    Leaves(strings) -> string_tree.from_strings(strings)
    Tree(tree) -> tree
    Blank -> string_tree.new()
  }
}

pub fn blank() -> View {
  Blank
}

pub fn perspective_simple(
  self: world.MobileInternal,
  actor: world.Mobile,
) -> PerspectiveSimple {
  case self.id == actor.id {
    True -> Self
    False -> Witness
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
  with num_graphemes: Int,
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
        with: num_graphemes,
        not_to_exceed: line_length,
      )

    <<>>, lines, curr_line, curr_word ->
      // Since there's nothing left to process, push the current word to the 
      // stack.
      //
      push_word(<<>>, lines, curr_line, curr_word, num_graphemes, line_length)

    <<" ", rest:bits>>, _, _, [] ->
      // if multiples of white space are encountered, ignore
      word_wrap_loop(
        process: rest,
        accumulate: acc,
        track: curr_line,
        and: [],
        with: num_graphemes,
        not_to_exceed: line_length,
      )

    <<" ", rest:bits>>, lines, curr_line, curr_word ->
      // If space is encounted, the current word is complete. Push onto the 
      // stack.
      push_word(rest, lines, curr_line, curr_word, num_graphemes, line_length)

    <<cp:utf8_codepoint, rest:bits>>, lines, curr_line, curr_word -> {
      // By default, simply build up the next word unless a space is encountered
      word_wrap_loop(
        process: rest,
        accumulate: lines,
        track: curr_line,
        and: [cp, ..curr_word],
        with: num_graphemes,
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
  with num_graphemes: Int,
  not_to_exceed line_length: Int,
) -> List(String) {
  let word = list.reverse(word) |> string.from_utf_codepoints()
  let word_length = string.length(word)

  let #(acc, curr_line, num_graphemes) = case
    num_graphemes + word_length >= line_length
  {
    True -> {
      // if the line_length is exceeded, attempt to hyphenate
      case hyphenate(word, with: num_graphemes, not_to_exceed: line_length) {
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
    False -> #(lines, [word, ..curr_line], word_length + num_graphemes)
  }

  word_wrap_loop(
    process: rest,
    accumulate: acc,
    track: curr_line,
    and: [],
    // + 1 is added to the count to account for white space
    with: num_graphemes + 1,
    not_to_exceed: line_length,
  )
}

// Returns a result of the hyphenation attempt: a tuple pair where the first
// element is the hyphenated word and the second is the remainder.
// If no hyphenation can be performed, returns the given unhyphenated word.
//
fn hyphenate(
  word: String,
  with num_graphemes: Int,
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
        with: num_graphemes,
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
  with num_graphemes: Int,
  not_to_exceed line_length: Int,
) -> Result(#(String, String), String) {
  case hyphenations {
    [first, ..rest] -> {
      let length = string.length(first)
      let num_graphemes = num_graphemes + length

      case num_graphemes >= line_length {
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
            with: num_graphemes,
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
