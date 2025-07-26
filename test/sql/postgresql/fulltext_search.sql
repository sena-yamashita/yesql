-- name: search_documents
-- 全文検索でドキュメントを検索
SELECT 
  id,
  title,
  ts_headline('english', content, query) as snippet,
  ts_rank(search_vector, query) as rank
FROM documents, 
     to_tsquery('english', :search_query) query
WHERE search_vector @@ query
ORDER BY rank DESC
LIMIT :limit

-- name: search_with_weights
-- 重み付き全文検索
SELECT 
  id,
  title,
  ts_rank(search_vector, query, 32) as rank
FROM documents,
     to_tsquery('english', :search_query) query
WHERE search_vector @@ query
  AND category = ANY(:categories)
ORDER BY rank DESC