-- MySQL CAST関数構文のテスト
SELECT 
  id,
  CAST(text_col AS SIGNED) as text_to_int,
  CAST(int_col AS CHAR) as int_to_text,
  date_col
FROM cast_test
WHERE text_col COLLATE utf8mb4_general_ci = CAST(:text_value AS CHAR)
  AND int_col > CAST(:int_value AS SIGNED)
  AND date_col = CAST(:date_value AS DATE)