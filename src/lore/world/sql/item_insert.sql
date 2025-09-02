INSERT INTO instance_items(item_id, inventory_id, container_id)
VALUES($1, $2, NULL)
RETURNING(item_instance_id)