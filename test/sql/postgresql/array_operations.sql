-- Find items that have any of the specified tags
SELECT id, name, tags
FROM items
WHERE CAST(:tag AS text) = ANY(tags)
ORDER BY id;

-- Find items with overlapping tags
SELECT id, name, tags
FROM items
WHERE tags && CAST(:tags AS text[])
ORDER BY id;

-- Add new tags to an item
UPDATE items
SET tags = array_cat(tags, CAST(:new_tags AS text[]))
WHERE id = CAST(:id AS integer)
RETURNING id, name, tags;