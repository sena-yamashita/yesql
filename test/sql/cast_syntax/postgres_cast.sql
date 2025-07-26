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