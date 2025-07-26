-- name: test_cast_syntax
-- MSSQL CAST/CONVERT構文のテスト
SELECT 
  id,
  CAST(text_col AS INT) as text_to_int,
  CAST(int_col AS NVARCHAR(50)) as int_to_text,
  date_col
FROM cast_test
WHERE text_col = CAST(:text_value AS NVARCHAR(255))
  AND int_col > CAST(:int_value AS INT)
  AND date_col = CAST(:date_value AS DATE)

-- name: mssql_convert_test
-- MSSQL CONVERT関数のテスト（スタイル付き）
SELECT 
  CONVERT(INT, :text_value) as converted_int,
  CONVERT(NVARCHAR(50), :int_value) as converted_text,
  CONVERT(NVARCHAR(30), :date_value, 103) as date_uk_format,
  CONVERT(NVARCHAR(30), :date_value, 101) as date_us_format