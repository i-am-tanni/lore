-- migrate:up
CREATE TABLE container(
  container_id INT NOT NULL,

  CONSTRAINT fk_container_id
	FOREIGN KEY(container_id)
	REFERENCES item(item_id)
	ON DELETE CASCADE
);


DROP TABLE container_kit;

CREATE TABLE container_item(
	container_id INT NOT NULL,
	item_id INT NOT NULL,
	item_quantity INT NOT NULL DEFAULT 1,

	PRIMARY KEY (container_id, item_id),

	CONSTRAINT fk_container_id
		FOREIGN KEY(container_id)
		REFERENCES item(item_id)
		ON DELETE CASCADE,

	CONSTRAINT fk_item_id
		FOREIGN KEY(item_id)
		REFERENCES item(item_id)
		ON DELETE CASCADE,

	CONSTRAINT chk_cannot_hold_self CHECK (container_id <> item_id),
  CONSTRAINT container_kit_quantity_check CHECK (item_quantity >= 0)
);

-- migrate:down

DROP TABLE container;
DROP TABLE container_item;