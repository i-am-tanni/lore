SELECT room_id, name FROM room
WHERE zone_id = $1
ORDER BY room_id;