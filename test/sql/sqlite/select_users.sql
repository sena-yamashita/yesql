-- SQLiteで全ユーザーを取得
SELECT * FROM users WHERE name = :name ORDER BY id;
