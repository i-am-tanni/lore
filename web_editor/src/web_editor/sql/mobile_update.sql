WITH updated_mobile AS (
    UPDATE mobile
    SET name = $2, short = $3, long = $4
    WHERE mobile_id = $1
    RETURNING mobile_id AS mobile_id
),
inserted_keywords AS (
    INSERT INTO keyword (keyword)
    SELECT unnest($5::text[])
    ON CONFLICT (keyword) DO UPDATE SET keyword = EXCLUDED.keyword
    RETURNING keyword_id
),
link_mobile_keywords AS (
    INSERT INTO mob_keyword (mobile_id, keyword_id)
    SELECT updated_mobile.mobile_id, inserted_keywords.keyword_id 
    FROM updated_mobile, inserted_keywords
    ON CONFLICT (mobile_id, keyword_id) DO NOTHING
)
SELECT mobile_id FROM updated_mobile;

