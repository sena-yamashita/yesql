-- name: test_cast_syntax
-- PostgreSQL :: キャスト構文のテスト
SELECT 
  id,
  text_col::integer as text_to_int,
  int_col::text as int_to_text,
  jsonb_col,
  array_col
FROM cast_test
WHERE text_col = :text_value::text
  AND int_col > :int_value::integer
  AND jsonb_col @> :jsonb_value::jsonb
  AND array_col && :array_value::integer[]

-- name: complex_cast_test
-- 複雑なキャストの組み合わせ
SELECT 
  :date::date as date_val,
  :timestamp::timestamptz as ts_val,
  :numeric::numeric(10,2) as num_val,
  :interval::interval as interval_val,
  :uuid::uuid as uuid_val,
  :json::json || :jsonb::jsonb as json_merge

-- name: cast_in_functions
-- 関数内でのキャスト使用
SELECT 
  array_agg(:value::text) as text_array,
  string_agg(:value::text, ',') as csv_string,
  sum(:number::integer) as total
FROM generate_series(1, 10)