-- SQLiteで複雑なJOINクエリ
SELECT u.name, u.age, COUNT(p.id) as post_count
FROM users u
LEFT JOIN posts p ON u.id = p.user_id
WHERE u.age >= :min_age
GROUP BY u.id, u.name, u.age
ORDER BY post_count DESC;