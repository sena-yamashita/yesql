-- name: get_hierarchy_tree
-- 再帰CTEで階層構造を取得
WITH RECURSIVE tree AS (
  -- 基底部: ルートノード
  SELECT id, name, parent_id, 0 as level, 
         ARRAY[id] as path,
         name::text as full_path
  FROM hierarchy
  WHERE parent_id = :root_id OR (:root_id IS NULL AND parent_id IS NULL)
  
  UNION ALL
  
  -- 再帰部: 子ノード
  SELECT h.id, h.name, h.parent_id, t.level + 1,
         t.path || h.id,
         t.full_path || ' > ' || h.name
  FROM hierarchy h
  JOIN tree t ON h.parent_id = t.id
  WHERE NOT h.id = ANY(t.path)  -- 循環を防ぐ
)
SELECT * FROM tree
ORDER BY path

-- name: calculate_subtree_aggregates
-- サブツリーの集計を計算
WITH RECURSIVE subtree AS (
  SELECT id, name, parent_id, value
  FROM nodes
  WHERE id = :node_id
  
  UNION ALL
  
  SELECT n.id, n.name, n.parent_id, n.value
  FROM nodes n
  JOIN subtree s ON n.parent_id = s.id
)
SELECT 
  COUNT(*) as node_count,
  SUM(value) as total_value,
  AVG(value)::numeric(10,2) as avg_value
FROM subtree