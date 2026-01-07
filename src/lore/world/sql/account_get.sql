SELECT * FROM account
WHERE LOWER(name) = LOWER($1);
