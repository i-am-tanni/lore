-- migrate:up
CREATE UNIQUE INDEX idx_unique_keyword_lower ON keyword (LOWER(keyword));

-- migrate:down

DROP INDEX idx_unique_keyword_lower;