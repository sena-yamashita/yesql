-- name: test_cast_syntax
-- Oracle CAST関数構文のテスト
SELECT 
  id,
  CAST(text_col AS NUMBER) as text_to_number,
  CAST(int_col AS VARCHAR2(50)) as int_to_text,
  date_col
FROM cast_test
WHERE text_col = CAST(:text_value AS VARCHAR2(255))
  AND int_col > CAST(:int_value AS NUMBER)
  AND date_col = CAST(:date_value AS DATE)

-- name: oracle_conversion_functions
-- Oracle変換関数のテスト
SELECT 
  TO_NUMBER(:text_value) as to_number_val,
  TO_CHAR(:int_value) as to_char_val,
  TO_DATE(:date_value, 'YYYY-MM-DD') as to_date_val,
  TO_TIMESTAMP(:timestamp_value, 'YYYY-MM-DD HH24:MI:SS') as to_timestamp_val
FROM dual