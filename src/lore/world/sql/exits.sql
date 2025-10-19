SELECT
  exit_id,
  keyword,
  from_room_id,
  to_room_id,
  door_id
FROM exit
WHERE is_active = TRUE;
