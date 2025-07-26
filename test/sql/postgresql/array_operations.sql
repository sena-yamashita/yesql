-- name: find_by_any_tag
-- 配列内のいずれかのタグを持つレコードを検索
SELECT id, name, tags
FROM items
WHERE :tag = ANY(tags)

-- name: find_by_overlapping_tags
-- 指定タグと重複するタグを持つレコードを検索
SELECT id, name, tags
FROM items
WHERE tags && :tags

-- name: add_tags_to_item
-- アイテムにタグを追加
UPDATE items
SET tags = array_cat(tags, :new_tags)
WHERE id = :id
RETURNING *