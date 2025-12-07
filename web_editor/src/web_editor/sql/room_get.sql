SELECT 
  r.room_id, 
  r.name, 
  r.zone_id, 
  r.symbol, 
  r.x, 
  r.y, 
  r.z, 
  r.description,
  z.name as zone_name
FROM room as r
INNER JOIN zone as z 
ON r.zone_id = z.zone_id
WHERE r.room_id = $1;