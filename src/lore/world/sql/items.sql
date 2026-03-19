SELECT
  i.item_id,
  i.name,
  i.short,
  i.long,
  c.container_id,
  k_agg.keywords as keywords
FROM item as i
LEFT JOIN container_kit as c 
  ON c.item_id = i.item_id
INNER JOIN (
  SELECT item_id, ARRAY_AGG(keyword_id) as keywords
  FROM item_keyword
  GROUP BY item_id
) as k_agg 
  ON k_agg.item_id = i.item_id;