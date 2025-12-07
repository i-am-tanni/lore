UPDATE room
SET zone_id=$2, name=$3, description=$4, symbol=$5, x=$6, y=$7, z=$8
WHERE room_id = $1