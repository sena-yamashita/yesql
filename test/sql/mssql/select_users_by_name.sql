-- MSSQLでユーザーを名前で検索
SELECT id, name, age 
FROM users 
WHERE name = :name
ORDER BY id