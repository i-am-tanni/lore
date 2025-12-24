import gleam/dict
import lore/server/my_list

pub fn insert_when_test() {
  let inserted = my_list.insert_when([1, 2, 4], 3, fn(x, _) { x > 2 })
  assert inserted == [1, 2, 3, 4]
}

pub fn group_by_test() {
  let grouped =
    my_list.group_by([1, 1, 1, 1, 2], fn(x) { #(x, x * 2) })
    |> dict.to_list()

  assert grouped == [#(1, [2, 2, 2, 2]), #(2, [4])]
}
