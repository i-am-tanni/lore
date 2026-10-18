INSERT INTO item(name, short, long)
VALUES ($1, $2, $3)
RETURNING item_id;
