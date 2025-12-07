SELECT 
  zone_id, 
  name 
FROM zone
WHERE zone_id = $1;