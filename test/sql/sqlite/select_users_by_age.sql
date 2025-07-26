-- name: select_users_by_age
-- SQLiteで年齢範囲でユーザーを検索
SELECT * FROM users WHERE age >= :min_age AND age <= :max_age ORDER BY age;