SELECT
  m.mobile_id,
  m.room_id,
  m.name,
  m.short,
  k_agg.keywords as keywords
FROM mobile as m
INNER JOIN (
  SELECT mobile_id, ARRAY_AGG(keyword_id) as keywords
  FROM mob_keyword
  GROUP BY mobile_id
) as k_agg
  ON k_agg.mobile_id = m.mobile_id
WHERE m.mobile_id = $1
;
