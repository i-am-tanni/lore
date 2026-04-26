-- migrate:up
CREATE TABLE keyword(
  keyword_id INT NOT NULL GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  keyword TEXT NOT NULL
);

CREATE TABLE item_keyword(
  item_id INT NOT NULL,
  keyword_id INT NOT NULL,
  PRIMARY KEY(item_id, keyword_id),

  CONSTRAINT fk_item_id
  FOREIGN KEY(item_id)
  REFERENCES item(item_id)
  ON DELETE CASCADE,

  CONSTRAINT fk_keyword_id
  FOREIGN KEY(keyword_id)
  REFERENCES keyword(keyword_id)
  ON DELETE CASCADE
);

CREATE TABLE mob_keyword(
  mobile_id INT NOT NULL,
  keyword_id INT NOT NULL,
  PRIMARY KEY(mobile_id, keyword_id),

  CONSTRAINT fk_mobile_id
  FOREIGN KEY(mobile_id)
  REFERENCES mobile(mobile_id)
  ON DELETE CASCADE,

  CONSTRAINT fk_keyword_id
  FOREIGN KEY(keyword_id)
  REFERENCES keyword(keyword_id)
  ON DELETE CASCADE
);

-- migrate:down
DROP TABLE item_keyword;
DROP TABLE mob_keyword;
DROP TABLE keyword;
