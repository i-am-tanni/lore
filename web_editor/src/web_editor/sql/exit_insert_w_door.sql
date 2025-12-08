-- recycle any inactive ids before inserting a new row
WITH reused AS (
  UPDATE exit
  SET
    from_room_id = $1,
    to_room_id = $2,
    keyword = $3,
    is_active = TRUE
  WHERE exit_id = (
    SELECT exit_id FROM exit
    WHERE is_active = FALSE
    LIMIT 1
  )
  RETURNING *
),

exit_inserted AS(
  -- If nothing was reused, create a new exit
  INSERT INTO exit (from_room_id, to_room_id, keyword, is_active)
  SELECT $1, $2, $3, TRUE
  WHERE NOT EXISTS (SELECT 1 FROM reused)
  RETURNING exit_id
),

door_side_reused AS (
  UPDATE door_side
  SET
    exit_id = (SELECT exit_id FROM exit_inserted),
    door_id = $4,
    is_active = TRUE
  WHERE door_side_id = (
    SELECT door_side_id FROM door_side
    WHERE is_active = FALSE
    LIMIT 1
  )
  RETURNING door_side_id
)

INSERT INTO door_side (exit_id, door_id)
SELECT exit_id, $4 FROM exit_inserted
WHERE NOT EXISTS (SELECT 1 FROM door_side_reused);
