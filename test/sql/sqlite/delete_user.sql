-- name: delete_user
-- SQLiteからユーザーを削除
DELETE FROM users WHERE id = :id;