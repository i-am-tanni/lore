SELECT d.door_id, d.access_state FROM door as d
INNER JOIN door_side as s ON s.door_id = d.door_id
INNER JOIN exit as e ON e.exit_id = s.exit_id
INNER JOIN room as r ON r.room_id = e.from_room_id
WHERE r.room_id = $1;
