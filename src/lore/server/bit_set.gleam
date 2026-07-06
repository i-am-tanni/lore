//// Functions for bit_sets to compact bools into an int
////

import gleam/int

pub type BitSet(a) {
  BitSet(Int)
}

pub fn add(bit_set: BitSet(a), flag: a, to_int_fun: fn(a) -> Int) -> BitSet(a) {
  let BitSet(bit_set) = bit_set

  flag
  |> to_int_fun
  |> int.bitwise_shift_left(1, _)
  |> int.bitwise_or(bit_set, _)
  |> BitSet
}

pub fn rmv(bit_set: BitSet(a), flag: a, to_int_fun: fn(a) -> Int) -> BitSet(a) {
  let BitSet(bit_set) = bit_set

  flag
  |> to_int_fun
  |> int.bitwise_shift_left(1, _)
  |> int.bitwise_and(bit_set, _)
  |> BitSet
}

pub fn toggle(
  bit_set: BitSet(a),
  flag: a,
  to_int_fun: fn(a) -> Int,
) -> BitSet(a) {
  let BitSet(bit_set) = bit_set

  flag
  |> to_int_fun
  |> int.bitwise_shift_left(1, _)
  |> int.bitwise_exclusive_or(bit_set, _)
  |> BitSet
}

pub fn in(bit_set: BitSet(a), flag: a, to_int_fun: fn(a) -> Int) -> Bool {
  let BitSet(bit_set) = bit_set
  let flag = to_int_fun(flag) |> int.bitwise_shift_left(1, _)
  int.bitwise_and(bit_set, flag) == flag
}
