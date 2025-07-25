-- name: insert_user
-- 新しいユーザーを挿入
INSERT INTO users (name, age)
VALUES (:name, :age)