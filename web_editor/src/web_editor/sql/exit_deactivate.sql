WITH deactivate_exit AS (
  UPDATE exit
  SET is_active = FALSE
  WHERE exit_id = $1
  RETURNING to_room_id
),

-- If exit has a door, deactivate the door and both sides

deactivate_door_side AS (
  UPDATE door_side
  SET is_active = FALSE
  WHERE exit_id = $1
  RETURNING door_id
),

deactivate_door AS (
  UPDATE door
  SET is_active = FALSE
  WHERE door_id = (SELECT door_id FROM deactivate_door_side)
  RETURNING door_id
)

UPDATE door_side
SET is_active = FALSE
WHERE
  exit_id = (SELECT to_room_id FROM deactivate_exit) AND
  door_id = (SELECT door_id FROM deactivate_door)
;
