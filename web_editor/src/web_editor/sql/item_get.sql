SELECT
    i.item_id,
    i.name,
    i.short,
    i.long,
    ARRAY(
        SELECT k.keyword
        FROM item_keyword AS ik
        INNER JOIN keyword AS k
            ON k.keyword_id = ik.keyword_id
        WHERE ik.item_id = i.item_id
    ) AS keywords
FROM item AS i
WHERE i.item_id = $1;
