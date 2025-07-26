-- name: update_user_age
-- ユーザーの年齢を更新
UPDATE users SET age = :age WHERE name = :name