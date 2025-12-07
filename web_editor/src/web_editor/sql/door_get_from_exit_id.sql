SELECT d.door_id FROM door as d
JOIN door_side as s ON s.door_id = d.door_id
WHERE s.exit_id = $1;
