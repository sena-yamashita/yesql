-- SQLiteでユーザーの年齢を更新
UPDATE users SET age = :age WHERE id = :id;