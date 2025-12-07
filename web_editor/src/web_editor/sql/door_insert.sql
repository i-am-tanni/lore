-- recycle any inactive ids before inserting a new row
WITH reused AS (
  UPDATE door
  SET
    access_state = $1,
    is_active = TRUE
  WHERE door_id = (
    SELECT door_id FROM door
    WHERE is_active = FALSE
    LIMIT 1
  )
  RETURNING *
)

-- If nothing was reused, create a new door
INSERT INTO door (access_state, is_active)
SELECT $1, TRUE
WHERE NOT EXISTS (SELECT 1 FROM reused)
RETURNING door_id;
