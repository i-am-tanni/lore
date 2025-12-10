-- recycle any inactive ids before inserting a new row
WITH reused_forward AS (
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

reused_reverse AS (
  UPDATE exit
  SET
    from_room_id = $2,
    to_room_id = $1,
    keyword = $4,
    is_active = TRUE
  WHERE exit_id = (
    SELECT exit_id FROM exit
    WHERE is_active = FALSE
    LIMIT 1
  )
  RETURNING *
)

-- If nothing was reused, create new
INSERT INTO exit (from_room_id, to_room_id, keyword, is_active)
SELECT $1, $2, $3, TRUE
WHERE NOT EXISTS (SELECT 1 FROM reused_forward)
UNION
SELECT $2, $1, $4, TRUE
WHERE NOT EXISTS (SELECT 1 FROM reused_reverse)
;
