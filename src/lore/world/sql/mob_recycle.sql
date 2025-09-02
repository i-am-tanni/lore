
-- Recycle an inactive mob instance id

UPDATE instance_mobs
SET room_instance_id = $2,
    character_id = $3,
    is_player = FALSE,
    is_active = TRUE
WHERE mob_instance_id = $1