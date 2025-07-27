-- MSSQL CONVERT関数のテスト（スタイル付き）
SELECT 
  CONVERT(INT, :text_value) as converted_int,
  CONVERT(NVARCHAR(50), :int_value) as converted_text,
  CONVERT(NVARCHAR(30), :date_value, 103) as date_uk_format,
  CONVERT(NVARCHAR(30), :date_value, 101) as date_us_format