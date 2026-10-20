-- migrate:up
ALTER TABLE mobile
DROP COLUMN room_id;

-- migrate:down
ALTER TABLE mobile
ADD COLUMN room_id int
CONSTRAINT fk_room_id
    FOREIGN KEY (room_id)
    REFERENCES room(room_id)
    ON DELETE CASCADE;
