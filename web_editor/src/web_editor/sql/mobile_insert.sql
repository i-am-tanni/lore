INSERT INTO mobile(name, short, long)
VALUES ($1, $2, $3)
RETURNING mobile_id;
