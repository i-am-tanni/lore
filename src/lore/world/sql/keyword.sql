-- query keywords + user names

WITH max_id AS (
    -- Get the current maximum ID from the keyword table
    SELECT COALESCE(MAX(keyword_id), 0) as start_val FROM keyword
)
SELECT keyword_id, keyword 
FROM keyword

UNION ALL
-- union with user names
SELECT 
    -- generate a keyword_id on the fly for account names
    (SELECT start_val FROM max_id) + ROW_NUMBER() OVER () AS keyword_id, 
    LOWER(name)
FROM account;