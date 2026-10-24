WITH updated_item AS (
    UPDATE item
    SET name = $2, short = $3, long = $4
    WHERE item_id = $1
    RETURNING item_id AS item_id
),
inserted_keywords AS (
    INSERT INTO keyword (keyword)
    SELECT DISTINCT unnest($5::text[])
    ON CONFLICT (keyword) DO UPDATE SET keyword = EXCLUDED.keyword
    RETURNING keyword_id
),
deleted AS (
    DELETE FROM item_keyword ik
    USING updated_item u
    WHERE ik.item_id = u.item_id
      AND NOT EXISTS (
          SELECT 1
          FROM inserted_keywords k
          WHERE k.keyword_id = ik.keyword_id
      )
),
link_item_keywords AS (
    INSERT INTO item_keyword (item_id, keyword_id)
    SELECT updated_item.item_id, inserted_keywords.keyword_id 
    FROM updated_item, inserted_keywords
    ON CONFLICT (item_id, keyword_id) DO NOTHING
)
SELECT item_id FROM updated_item;

