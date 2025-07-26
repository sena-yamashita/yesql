-- 配列フィールドでの複雑な検索（実使用例）
SELECT 
  id,
  name,
  tags,
  prices,
  features,
  -- 最低価格の計算
  (SELECT MIN(unnest) FROM unnest(prices))::numeric(10,2) as min_price,
  -- タグの数
  array_length(tags, 1)::integer as tag_count,
  -- 必須タグとの重複
  tags && :required_tags::text[] as has_required_tags
FROM products
WHERE 
  -- 必須タグを全て含む
  tags @> :required_tags::text[]
  -- 除外タグを含まない
  AND NOT (tags && :excluded_tags::text[])
  -- 価格条件（配列内の最小値で判定）
  AND (SELECT MIN(unnest) FROM unnest(prices)) <= :max_price::numeric
ORDER BY 
  -- タグの一致度でソート
  cardinality(tags & :required_tags::text[]) DESC,
  min_price ASC