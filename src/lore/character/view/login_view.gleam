import lore/character/view.{type View}

pub fn login() -> View {
  "Welcome to the server!"
  |> view.Leaf
}

pub fn name() -> View {
  "Enter a name: "
  |> view.Leaf
}

pub fn password(name: String) -> View {
  ["Enter password for ", name, ": "]
  |> view.Leaves
}

pub fn new_name_confirm(name: String) -> View {
  [
    "There is no account associated with ",
    name,
    ".\n",
    "Would you like to create one? (y/n): ",
  ]
  |> view.Leaves
}

pub fn name_abort() -> View {
  "OK, what name would you like to login as? "
  |> view.Leaf
}

pub fn new_password1() -> View {
  "Enter a password for this account: "
  |> view.Leaf
}

pub fn new_password2() -> View {
  "Enter the password a second time: "
  |> view.Leaf
}

pub fn password_mismatch_err() -> View {
  "Passwords do not match. Please enter again: "
  |> view.Leaf
}

pub fn password_invalid() -> View {
  "Password is invalid. Try again: "
  |> view.Leaf
}

pub fn password_err() -> View {
  "Incorrect password. Try again: "
  |> view.Leaf
}

pub fn greeting(name: String) -> View {
  ["Hello, ", name, "!"]
  |> view.Leaves
}
