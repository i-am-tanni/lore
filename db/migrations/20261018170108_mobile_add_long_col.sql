-- migrate:up
ALTER TABLE mobile
ADD COLUMN long text;

-- migrate:down
ALTER TABLE
DROP COLUMN long;
