import ming/character/view.{type View}

pub fn login() -> View {
  "Welcome to the server!"
  |> view.Leaf
}

pub fn name() -> View {
  "Enter a name: "
  |> view.Leaf
}

pub fn greeting(name: String) -> View {
  ["Hello, ", name, "!"]
  |> view.Leaves
}
