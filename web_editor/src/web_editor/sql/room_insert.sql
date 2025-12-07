INSERT INTO room (zone_id, name, description, symbol, x, y, z)
VALUES ($1, $2, $3, $4, $5, $6, $7)
RETURNING room_id;