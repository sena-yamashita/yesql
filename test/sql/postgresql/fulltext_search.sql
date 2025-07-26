-- name: search_documents
-- Full text search with ranking
SELECT 
  id,
  title,
  content,
  ts_rank(search_vector, query) as rank
FROM documents, to_tsquery('english', CAST(:search_query AS text)) query
WHERE search_vector @@ query
ORDER BY rank DESC
LIMIT CAST(:limit AS integer);

-- name: search_with_weights
-- Search with category filtering
SELECT 
  id,
  title,
  content,
  category,
  ts_rank(search_vector, query) as rank
FROM documents, to_tsquery('english', CAST(:search_query AS text)) query
WHERE 
  search_vector @@ query
  AND category = ANY(CAST(:categories AS text[]))
ORDER BY rank DESC;