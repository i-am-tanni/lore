import gleam/dict
import lore/server/my_dict

pub fn find_nth_test() {
  let dict =
    [#(1, "red"), #(2, "blue"), #(3, "yellow"), #(4, "red")]
    |> dict.from_list

  let result = my_dict.find_nth(dict, 2, fn(_, val) { val == "red" })

  assert result == Ok(#(4, "red"))
}
