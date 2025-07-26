-- name: find_users_by_tag
-- JSONB配列内のタグで検索
SELECT id, data
FROM users
WHERE data->'tags' @> :tag

-- name: find_users_by_attributes
-- JSONB属性で検索
SELECT id, data
FROM users
WHERE data @> :attributes

-- name: update_user_data
-- JSONB データの更新
UPDATE users
SET data = data || :new_data
WHERE id = :id
RETURNING *