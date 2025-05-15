pub type Item {
  Item
}

pub type ItemTemplate {
  Loaded(Item)
  Loading
}

/// An instance of an item
/// 
pub type ItemInstance {
  ItemInstance(
    id: String,
    keywords: List(String),
    item: ItemTemplate,
    short: String,
  )
}
