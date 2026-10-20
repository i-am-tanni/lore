INSERT INTO item_keyword(item_id, keyword_id)
VALUES ($1, $2)
ON CONFLICT (item_id, keyword_id) DO NOTHING;
