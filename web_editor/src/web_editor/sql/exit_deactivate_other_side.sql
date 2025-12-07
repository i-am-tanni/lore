UPDATE exit
SET is_active = FALSE
WHERE from_room_id = $1 AND keyword = $2;
