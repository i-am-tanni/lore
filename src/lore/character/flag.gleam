//// Functions for bitfields to compact bools into an int
////

import gleam/int

pub type AffectFlag {
  SuperInvisible
  GodMode
  AutoRevive
}

pub type Affects {
  Affects(Int)
}

pub fn affect_add(affects: Affects, flag: AffectFlag) -> Affects {
  let Affects(flags) = affects
  Affects(add(flags, affect_to_int(flag)))
}

pub fn affect_subtract(affects: Affects, flag: AffectFlag) -> Affects {
  let Affects(flags) = affects
  Affects(subtract(flags, affect_to_int(flag)))
}

pub fn affect_toggle(affects: Affects, flag: AffectFlag) -> Affects {
  let Affects(flags) = affects
  Affects(toggle(flags, affect_to_int(flag)))
}

pub fn affect_has(affects: Affects, flag: AffectFlag) -> Bool {
  let Affects(flags) = affects
  has(flags, affect_to_int(flag))
}

fn add(flags: Int, flag: Int) -> Int {
  int.bitwise_or(flags, flag)
}

fn subtract(flags: Int, flag: Int) -> Int {
  int.bitwise_and(flags, int.bitwise_not(flag))
}

fn toggle(flags: Int, flag: Int) -> Int {
  int.bitwise_exclusive_or(flags, flag)
}

fn has(flags: Int, flag: Int) -> Bool {
  int.bitwise_and(flags, flag) == flag
}

fn affect_to_int(flag: AffectFlag) -> Int {
  case flag {
    SuperInvisible -> int.bitwise_shift_left(1, 0)
    GodMode -> int.bitwise_shift_left(1, 1)
    AutoRevive -> int.bitwise_shift_left(1, 2)
  }
}
