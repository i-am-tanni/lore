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
)

-- If nothing was reused, create a new exit
INSERT INTO exit (from_room_id, to_room_id, keyword, is_active)
SELECT $1, $2, $3, TRUE
WHERE NOT EXISTS (SELECT 1 FROM reused);
