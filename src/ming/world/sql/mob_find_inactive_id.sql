-- Recycle ids where possible of inactive mob instances
SELECT mob_instance_id FROM instance_mobs
WHERE is_active = false
LIMIT 1
