SELECT
  e.exit_id,
  e.keyword,
  e.from_room_id,
  e.to_room_id,
  d.door_id
FROM exit as e
LEFT JOIN door_side as d
  ON e.exit_id = d.exit_id AND d.is_active
WHERE e.is_active = TRUE;
