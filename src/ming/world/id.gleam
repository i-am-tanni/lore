import gleam/bit_array
import gleam/int
import gleam/list

/// An id generated during runtime.
/// 
pub type Id(a) {
  Id(Int)
}

/// Generates random 32 bit base-16 encoded string identifier.
/// 
/// ## Example
/// ```gleam
/// id.generate()
/// // -> 3D40AD6B
/// ```
/// 
pub fn generate() -> String {
  list.range(1, 4)
  |> list.map(fn(_) { <<int.random(256)>> })
  |> bit_array.concat()
  |> bit_array.base16_encode
}

pub fn unwrap(id: Id(a)) -> Int {
  let Id(a) = id
  a
}
