-- name: find_users_by_tag
-- Find users that have a specific tag in their JSONB data
SELECT id, data
FROM users
WHERE data->'tags' @> CAST(:tag AS jsonb)
ORDER BY id;

-- name: find_users_by_attributes
-- Find users by JSONB attributes
SELECT id, data
FROM users
WHERE data @> CAST(:attributes AS jsonb)
ORDER BY id;

-- name: update_user_data
-- Update user JSONB data while preserving existing fields
UPDATE users
SET data = data || CAST(:new_data AS jsonb)
WHERE id = CAST(:id AS integer)
RETURNING id, data;