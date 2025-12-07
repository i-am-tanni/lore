SELECT exit_id, door_id FROM door_side
WHERE exit_id = ANY($1);
