-- name: search_users_by_jsonb
-- 複雑なJSONB検索クエリ（実使用例）
SELECT 
  id,
  data,
  data->>'name' as name,
  (data->>'age')::integer as age,
  data->'tags' as tags,
  created_at
FROM users
WHERE 
  -- 年齢条件（数値へのキャスト）
  (data->>'age')::integer >= :min_age::integer
  -- タグ検索（JSONB配列の包含チェック）
  AND data->'tags' @> :tags::jsonb
  -- ネストしたJSONBフィールドの検索
  AND data->'profile'->>'city' = :city::text
ORDER BY (data->>'age')::integer DESC