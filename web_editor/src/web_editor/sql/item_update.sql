UPDATE item
SET name=$2, short=$3, long=$4
WHERE item_id = $1;
