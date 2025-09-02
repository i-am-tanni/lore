INSERT INTO instance_mobs(
  character_id, 
  room_instance_id, 
  inventory_id, 
  is_active, 
  is_player
)
VALUES($1, $2, $3, TRUE, FALSE)
RETURNING(room_instance_id)
