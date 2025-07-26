-- Get full hierarchy tree with levels
WITH RECURSIVE tree AS (
  SELECT 
    id, 
    name, 
    parent_id, 
    0 as level,
    name as full_path
  FROM hierarchy
  WHERE parent_id IS NULL OR parent_id = CAST(:root_id AS integer)
  
  UNION ALL
  
  SELECT 
    h.id, 
    h.name, 
    h.parent_id, 
    t.level + 1,
    t.full_path || ' > ' || h.name
  FROM hierarchy h
  JOIN tree t ON h.parent_id = t.id
)
SELECT id, name, parent_id, level, full_path
FROM tree
ORDER BY level, name;

-- Calculate aggregates for a subtree
WITH RECURSIVE subtree AS (
  SELECT id, name, parent_id, value
  FROM nodes
  WHERE id = CAST(:node_id AS integer)
  
  UNION ALL
  
  SELECT n.id, n.name, n.parent_id, n.value
  FROM nodes n
  JOIN subtree s ON n.parent_id = s.id
)
SELECT 
  COUNT(*) as node_count,
  SUM(value) as total_value,
  AVG(value)::numeric(10,2) as avg_value
FROM subtree;