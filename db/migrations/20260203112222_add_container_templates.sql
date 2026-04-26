-- migrate:up

CREATE TABLE container_kit (
  container_id INT NOT NULL,
  item_id INT NOT NULL,
  quantity INT NOT NULL CHECK (quantity >= 0) DEFAULT 1,

  CONSTRAINT fk_container_id FOREIGN KEY (container_id)
    REFERENCES item(item_id) ON DELETE CASCADE,

  CONSTRAINT fk_item_contained FOREIGN KEY (item_id)
    REFERENCES item(item_id) ON DELETE CASCADE,

  PRIMARY KEY (container_id, item_id),

  CONSTRAINT chk_cannot_hold_self
    CHECK (container_id <> item_id)
);

CREATE TABLE inventory_kit (
  mobile_id INT NOT NULL,
  item_id INT NOT NULL,
  quantity INT NOT NULL CHECK (quantity >= 0) DEFAULT 1,

  CONSTRAINT fk_mobile_inventory_kit FOREIGN KEY (mobile_id)
    REFERENCES mobile(mobile_id) ON DELETE CASCADE,

  CONSTRAINT fk_item_in_inventory_kit FOREIGN KEY (item_id)
    REFERENCES item(item_id) ON DELETE CASCADE,

  PRIMARY KEY (mobile_id, item_id)
);

-- migrate:down
DROP TABLE container_kit;

DROP TABLE inventory_kit;
