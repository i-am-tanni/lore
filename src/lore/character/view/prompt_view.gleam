import lore/character/view.{type View}

pub fn prompt() -> View {
  view.Leaf("> ")
}
