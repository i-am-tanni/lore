SELECT
  i.item_id,
  i.name,
  i.short,
  i.long,
  i.keywords,
  c.container_id
FROM item as i
LEFT JOIN container_kit as c
  ON c.item_id = i.item_id;
