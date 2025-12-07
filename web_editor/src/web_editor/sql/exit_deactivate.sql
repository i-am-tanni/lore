UPDATE exit
SET
  is_active = FALSE
WHERE
  exit_id = $1
RETURNING
  exit_id, to_room_id, keyword;
