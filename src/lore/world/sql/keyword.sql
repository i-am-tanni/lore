-- query keywords + user names

SELECT keyword_id, keyword 
FROM keyword

UNION ALL
-- union with user names
SELECT 
    -- reserve keywords above 10,000,000 for account names
    10000000 + account_id AS keyword_id, 
    LOWER(name)
FROM account;