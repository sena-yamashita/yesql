-- DuckDB :: キャスト構文のテスト（PostgreSQL互換）
SELECT 
  id,
  text_col::INTEGER as text_to_int,
  int_col::VARCHAR as int_to_text,
  decimal_col
FROM cast_test
WHERE text_col = :text_value::VARCHAR
  AND int_col > :int_value::INTEGER

-- DuckDB特有のキャスト
SELECT 
  :date::DATE as date_val,
  :timestamp::TIMESTAMP as ts_val,
  :decimal::DECIMAL(10,2) as decimal_val,
  :list::INTEGER[] as int_list,
  :struct::STRUCT(a INTEGER, b VARCHAR) as struct_val