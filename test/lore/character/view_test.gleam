import gleam/list
import gleam/string
import gleeunit/should
import hyphenation
import hyphenation/language
import lore/character/view

const lorem_ipsum = "Gleam is a friendly language for building type-safe systems that scale! The power of a type system, the expressiveness of functional programming, and the reliability of the highly concurrent, fault tolerant Erlang runtime, with a familiar and modern syntax."

pub fn hyphenation_test() {
  let hyphenator = hyphenation.hyphenator(language.EnglishUS)

  hyphenation.hyphenate("building", hyphenator)
  |> should.equal(["build", "ing"])
}

pub fn word_wrap_test() {
  let expected =
    "Gleam is a friendly language for build-
ing type-safe systems that scale! The
power of a type system, the expressive-
ness of functional programming, and
the reliability of the highly concur-
rent, fault tolerant Erlang runtime,
with a familiar and modern syntax."

  let hyphenated =
    view.word_wrap(lorem_ipsum, 39)
    |> list.intersperse("\n")
    |> string.concat()

  assert expected == hyphenated
}
