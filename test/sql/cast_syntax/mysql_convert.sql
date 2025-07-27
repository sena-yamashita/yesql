-- MySQL CONVERT関数のテスト
SELECT 
  CONVERT(:text_value, SIGNED INTEGER) as converted_int,
  CONVERT(:int_value, CHAR) as converted_char,
  CONVERT(:date_value USING utf8mb4) as converted_charset