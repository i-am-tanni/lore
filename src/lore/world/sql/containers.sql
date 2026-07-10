SELECT 
  c.container_id, 
  i.item_id, 
  COALESCE(i.item_quantity, 0) AS item_quantity
FROM container as c
LEFT JOIN container_item as i
ON c.container_id = i.container_id;
