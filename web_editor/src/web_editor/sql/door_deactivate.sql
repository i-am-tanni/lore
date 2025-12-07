UPDATE door
SET is_active = FALSE
WHERE door_id = $1;