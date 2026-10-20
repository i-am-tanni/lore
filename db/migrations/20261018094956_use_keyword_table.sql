-- migrate:up
ALTER TABLE item
DROP COLUMN keywords;

ALTER TABLE mobile
DROP COLUMN keywords;

-- migrate:down
