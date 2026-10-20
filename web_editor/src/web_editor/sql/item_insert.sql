WITH inserted_item AS (
    INSERT INTO item (name, short, long)
    VALUES ($1, $2, $3)
    RETURNING item_id
),
inserted_keywords AS (
    INSERT INTO keyword (keyword)
    SELECT unnest($4::text[])
    ON CONFLICT (keyword) DO UPDATE SET keyword = EXCLUDED.keyword
    RETURNING keyword_id
),
link_item_keywords AS (
    INSERT INTO item_keyword (item_id, keyword_id)
    SELECT inserted_item.item_id, inserted_keywords.keyword_id 
    FROM inserted_item, inserted_keywords
    ON CONFLICT (item_id, keyword_id) DO NOTHING
)
SELECT item_id FROM inserted_item;
