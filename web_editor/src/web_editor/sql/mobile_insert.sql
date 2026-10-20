WITH inserted_mobile AS (
    INSERT INTO mobile (name, short, long)
    VALUES ($1, $2, $3)
    RETURNING mobile_id
),
inserted_keywords AS (
    INSERT INTO keyword (keyword)
    SELECT unnest($4::text[])
    ON CONFLICT (keyword) DO UPDATE SET keyword = EXCLUDED.keyword
    RETURNING keyword_id
),
link_mobile_keywords AS (
    INSERT INTO mob_keyword (mobile_id, keyword_id)
    SELECT inserted_mobile.mobile_id, inserted_keywords.keyword_id 
    FROM inserted_mobile, inserted_keywords
    ON CONFLICT (mobile_id, keyword_id) DO NOTHING
)
SELECT mobile_id FROM inserted_mobile;
