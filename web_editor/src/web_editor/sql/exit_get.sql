SELECT
  e.exit_id,
  e.keyword,
  e.from_room_id,
  e.to_room_id,
  e.is_active,
  d.door_id
FROM exit as e
LEFT JOIN door_side as d ON d.exit_id = e.exit_id
WHERE from_room_id = 1 AND is_active = TRUE;
