-- Recycle ids where possible of inactive item instances
SELECT item_instance_id FROM instance_items
WHERE is_active = false
LIMIT 1
