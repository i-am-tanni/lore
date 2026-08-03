//// Takes a record that contains strings portraying an event from different
//// perspectives and transforms the string for the observer.
////  
//// Basic Variables
//// - $n - Subject name
//// - $e - He / She pronouns
//// - $m - Him / Her pronouns
//// - $s - His / Her pronouns
//// - $mself - Himself / Herself pronouns
//// 
//// Victim Variables
//// - $N - Victim name
//// - $E - Victim he / she
//// - $M - Victim him / her
//// - $S - Victim his / her
//// - $MSELF - Victim himself, herself
////

import gleam/bit_array
import gleam/bytes_tree.{type BytesTree}
import gleam/option.{type Option, None, Some}
import gleam/result

pub const feminine = Pronoun(
  he: "she",
  him: "her",
  his: "her",
  himself: "herself",
)

pub const masculine = Pronoun(
  he: "he",
  him: "him",
  his: "his",
  himself: "himself",
)

pub const neutral = Pronoun(
  he: "they",
  him: "them",
  his: "their",
  himself: "themself",
)

pub const you = Pronoun(he: "you", him: "you", his: "your", himself: "yourself")

/// A text record that considers multiple perspectives
/// 
pub type EventText {
  /// Auto is an act that can target self or another victim
  /// 
  EventTextAuto(
    p3: String,
    p1: String,
    p2: String,
    p1_auto: String,
    p3_auto: String,
  )
  /// Vict is an act that can target a victim, but NOT the self
  /// 
  EventTextVict(p3: String, p1: String, p2: String)
  /// An act that has no victim that can witness the act
  /// 
  EventText(p3: String, p1: String)
}

pub type PronounKind {
  Feminine
  Masculine
  Neutral
}

/// A set of pronouns
/// 
pub type Pronoun {
  /// Note: These are masculine because he/him/his/himself is clearer
  /// than she/her/her/herself
  /// 
  Pronoun(he: String, him: String, his: String, himself: String)
}

pub type Participant {
  Participant(id: Int, name: String, pronoun: Pronoun)
}

// The perspective the action is being observed from
//
type Perspective {
  // Subject is from the subject's pov
  Subject
  // Victim is from the victim's pov
  Victim
  // Witness is from an independent observer's pov
  Witness
  // From the subject's pov if they target themself
  SubjectAuto
  // From an independent observer's pov if the subject targets themself
  WitnessAuto
}

pub fn render(
  witness: Participant,
  subject: Participant,
  victim: Option(Participant),
  text: EventText,
) -> String {
  case victim {
    Some(victim) -> {
      let perspective = perspective_adv(witness.id, subject.id, victim.id)
      let victim = case text {
        // Victim override if you targeted yourself and there is no special text
        // for doing so!
        EventTextVict(..) if perspective == SubjectAuto ->
          Participant(..victim, name: "yourself", pronoun: you)
        _ -> victim
      }

      select(text, perspective)
      |> replace_subject_victim(subject, victim)
    }

    None ->
      select(text, perspective_simple(witness.id, subject.id))
      |> replace_subject(subject)
  }
}

pub fn pronouns(choice: PronounKind) -> Pronoun {
  case choice {
    Feminine -> feminine
    Masculine -> masculine
    Neutral -> neutral
  }
}

fn select(text: EventText, perspective: Perspective) -> String {
  case perspective, text {
    Subject, _ if text.p1 == "" -> text.p3
    Subject, _ -> text.p1
    Witness, _ -> text.p3
    Victim, EventTextVict(p2:, ..) -> p2
    Victim, EventTextAuto(p2:, ..) -> p2
    SubjectAuto, EventTextAuto(p1_auto:, ..) -> p1_auto
    WitnessAuto, EventTextAuto(p3_auto:, ..) -> p3_auto
    // Error recovery
    Victim, EventText(p3:, ..) -> p3
    SubjectAuto, _ -> text.p1
    WitnessAuto, _ -> text.p3
  }
}

fn perspective_simple(witness: Int, subject: Int) -> Perspective {
  case True {
    _ if subject == witness -> Subject
    _ -> Witness
  }
}

fn perspective_adv(witness: Int, subject: Int, victim: Int) -> Perspective {
  case True {
    _ if witness == subject && subject == victim -> SubjectAuto
    _ if witness == subject -> Subject
    _ if witness == victim -> Victim
    _ if subject == victim -> WitnessAuto
    _ -> Witness
  }
}

fn replace_subject(s: String, subject: Participant) -> String {
  bit_array.from_string(s)
  |> replace_subject_loop(subject, bytes_tree.new())
  |> result.unwrap("")
}

// For strings where there is no direct object to witness itself being acted
// upon.
fn replace_subject_loop(
  s: BitArray,
  subject: Participant,
  acc: BytesTree,
) -> Result(String, Nil) {
  let pronouns = subject.pronoun
  case s {
    <<>> ->
      acc
      |> bytes_tree.to_bit_array
      |> bit_array.to_string

    // subject name
    <<"$n", rest:bits>> ->
      replace_subject_loop(
        rest,
        subject,
        bytes_tree.append_string(acc, subject.name),
      )

    // he / her type pronouns
    <<"$e", rest:bits>> ->
      replace_subject_loop(
        rest,
        subject,
        bytes_tree.append_string(acc, pronouns.he),
      )

    // his / hers type pronouns
    <<"$s", rest:bits>> ->
      replace_subject_loop(
        rest,
        subject,
        bytes_tree.append_string(acc, pronouns.his),
      )

    // himself / herself type pronouns
    <<"$mself", rest:bits>> ->
      replace_subject_loop(
        rest,
        subject,
        bytes_tree.append_string(acc, pronouns.himself),
      )

    // him / hers type pronouns
    <<"$m", rest:bits>> ->
      replace_subject_loop(
        rest,
        subject,
        bytes_tree.append_string(acc, pronouns.him),
      )

    <<x:8, rest:bits>> ->
      replace_subject_loop(rest, subject, bytes_tree.append(acc, <<x>>))

    _ -> replace_subject_loop(<<>>, subject, acc)
  }
}

// For strings where a witness can be acted upon.
fn replace_subject_victim(
  s: String,
  subject: Participant,
  victim: Participant,
) -> String {
  bit_array.from_string(s)
  |> replace_subject_victim_loop(subject, victim, bytes_tree.new())
  |> result.unwrap("")
}

fn replace_subject_victim_loop(
  s: BitArray,
  subject: Participant,
  victim: Participant,
  acc: BytesTree,
) -> Result(String, Nil) {
  case s {
    <<>> ->
      acc
      |> bytes_tree.to_bit_array
      |> bit_array.to_string

    <<"$n", rest:bits>> ->
      replace_subject_victim_loop(
        rest,
        subject,
        victim,
        bytes_tree.append_string(acc, subject.name),
      )

    <<"$e", rest:bits>> ->
      replace_subject_victim_loop(
        rest,
        subject,
        victim,
        bytes_tree.append_string(acc, subject.pronoun.he),
      )

    <<"$s", rest:bits>> ->
      replace_subject_victim_loop(
        rest,
        subject,
        victim,
        bytes_tree.append_string(acc, subject.pronoun.his),
      )

    <<"$mself", rest:bits>> ->
      replace_subject_victim_loop(
        rest,
        subject,
        victim,
        bytes_tree.append_string(acc, subject.pronoun.himself),
      )

    <<"$m", rest:bits>> ->
      replace_subject_victim_loop(
        rest,
        subject,
        victim,
        bytes_tree.append_string(acc, subject.pronoun.him),
      )

    <<"$N", rest:bits>> ->
      replace_subject_victim_loop(
        rest,
        subject,
        victim,
        bytes_tree.append_string(acc, victim.name),
      )

    <<"$E", rest:bits>> ->
      replace_subject_victim_loop(
        rest,
        subject,
        victim,
        bytes_tree.append_string(acc, victim.pronoun.he),
      )

    <<"$S", rest:bits>> ->
      replace_subject_victim_loop(
        rest,
        subject,
        victim,
        bytes_tree.append_string(acc, victim.pronoun.his),
      )

    <<"$MSELF", rest:bits>> ->
      replace_subject_victim_loop(
        rest,
        subject,
        victim,
        bytes_tree.append_string(acc, victim.pronoun.himself),
      )

    <<"$M", rest:bits>> ->
      replace_subject_victim_loop(
        rest,
        subject,
        victim,
        bytes_tree.append_string(acc, victim.pronoun.him),
      )

    <<x:8, rest:bits>> ->
      replace_subject_victim_loop(
        rest,
        subject,
        victim,
        bytes_tree.append(acc, <<x>>),
      )

    _ -> replace_subject_victim_loop(<<>>, subject, victim, acc)
  }
}
