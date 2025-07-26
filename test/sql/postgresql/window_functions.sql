-- name: sales_with_running_total
-- 売上の累積合計を計算
SELECT 
  id,
  product,
  amount,
  sale_date,
  SUM(amount) OVER (PARTITION BY product ORDER BY sale_date) as running_total,
  ROW_NUMBER() OVER (PARTITION BY product ORDER BY sale_date) as row_num
FROM sales
WHERE sale_date BETWEEN :start_date AND :end_date
ORDER BY product, sale_date

-- name: rank_products_by_sales
-- 製品を売上でランク付け
SELECT 
  product,
  SUM(amount) as total_sales,
  RANK() OVER (ORDER BY SUM(amount) DESC) as sales_rank,
  PERCENT_RANK() OVER (ORDER BY SUM(amount) DESC) as percentile
FROM sales
WHERE sale_date >= :since
GROUP BY product