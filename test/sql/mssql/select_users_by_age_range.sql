-- name: select_users_by_age_range
-- 年齢範囲でユーザーを検索
SELECT id, name, age
FROM users
WHERE age >= :min_age AND age <= :max_age
ORDER BY age, id