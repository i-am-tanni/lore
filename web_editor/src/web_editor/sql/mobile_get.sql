SELECT
    i.mobile_id,
    i.name,
    i.short,
    i.long,
    ARRAY(
        SELECT k.keyword
        FROM mob_keyword AS ik
        INNER JOIN keyword AS k
            ON k.keyword_id = ik.keyword_id
        WHERE ik.mobile_id = i.mobile_id
    ) AS keywords
FROM mobile AS i
WHERE i.mobile_id = $1;
