-- MSSQL CAST/CONVERT構文のテスト
SELECT 
  id,
  CAST(text_col AS INT) as text_to_int,
  CAST(int_col AS NVARCHAR(50)) as int_to_text,
  date_col
FROM cast_test
WHERE text_col = CAST(:text_value AS NVARCHAR(255))
  AND int_col > CAST(:int_value AS INT)
  AND date_col > CAST(:date_value AS DATE)