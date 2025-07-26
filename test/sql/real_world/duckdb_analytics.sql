-- name: analyze_sales
-- DuckDBでの売上分析クエリ（実使用例）
WITH monthly_sales AS (
  SELECT 
    date_trunc('month', date)::DATE as month,
    category::VARCHAR as category,
    SUM(amount)::DECIMAL(10,2) as total_amount,
    COUNT(*)::INTEGER as transaction_count,
    AVG(amount)::DECIMAL(10,2) as avg_amount
  FROM sales_data
  WHERE 
    date BETWEEN :start_date::DATE AND :end_date::DATE
    AND amount >= :min_amount::DECIMAL
  GROUP BY month, category
),
category_rank AS (
  SELECT 
    month,
    category,
    total_amount,
    transaction_count,
    avg_amount,
    -- カテゴリ別ランキング
    RANK() OVER (PARTITION BY month ORDER BY total_amount DESC)::INTEGER as rank,
    -- 前月比
    LAG(total_amount, 1) OVER (PARTITION BY category ORDER BY month)::DECIMAL(10,2) as prev_month_amount
  FROM monthly_sales
)
SELECT 
  month,
  category,
  total_amount,
  transaction_count,
  avg_amount,
  rank,
  -- 成長率の計算
  CASE 
    WHEN prev_month_amount IS NOT NULL AND prev_month_amount > 0 
    THEN ((total_amount - prev_month_amount) / prev_month_amount * 100)::DECIMAL(5,2)
    ELSE NULL 
  END as growth_rate
FROM category_rank
ORDER BY month, rank