-- migrate:up
ALTER TABLE mobile
ADD COLUMN long text NOT NULL DEFAULT ''

-- migrate:down
ALTER TABLE mobile
DROP COLUMN long;
