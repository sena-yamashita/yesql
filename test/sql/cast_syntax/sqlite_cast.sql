-- SQLite CAST関数構文のテスト
SELECT 
  id,
  CAST(text_col AS INTEGER) as text_to_int,
  CAST(int_col AS TEXT) as int_to_text,
  real_col
FROM cast_test
WHERE text_col = CAST(:text_value AS TEXT)
  AND int_col > CAST(:int_value AS INTEGER)
  AND real_col > CAST(:real_value AS REAL)

-- SQLiteの型親和性テスト
SELECT 
  typeof(CAST(:value AS INTEGER)) as int_type,
  typeof(CAST(:value AS TEXT)) as text_type,
  typeof(CAST(:value AS REAL)) as real_type,
  typeof(CAST(:value AS BLOB)) as blob_type