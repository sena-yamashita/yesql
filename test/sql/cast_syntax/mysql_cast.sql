-- name: test_cast_syntax
-- MySQL CAST関数構文のテスト
SELECT 
  id,
  CAST(text_col AS SIGNED) as text_to_int,
  CAST(int_col AS CHAR) as int_to_text,
  date_col
FROM cast_test
WHERE text_col = CAST(:text_value AS CHAR)
  AND int_col > CAST(:int_value AS SIGNED)
  AND date_col = CAST(:date_value AS DATE)

-- name: mysql_convert_test
-- MySQL CONVERT関数のテスト
SELECT 
  CONVERT(:text_value, SIGNED INTEGER) as converted_int,
  CONVERT(:int_value, CHAR) as converted_char,
  CONVERT(:date_value USING utf8mb4) as converted_charset