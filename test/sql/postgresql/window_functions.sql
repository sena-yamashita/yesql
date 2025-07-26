-- Get sales with running total using window functions
SELECT 
  product,
  amount,
  sale_date,
  SUM(amount) OVER (PARTITION BY product ORDER BY sale_date) as running_total
FROM sales
WHERE sale_date BETWEEN CAST(:start_date AS date) AND CAST(:end_date AS date)
ORDER BY product, sale_date;

-- Rank products by total sales
SELECT 
  product,
  SUM(amount) as total_sales,
  RANK() OVER (ORDER BY SUM(amount) DESC) as sales_rank
FROM sales
WHERE sale_date >= CAST(:since AS date)
GROUP BY product
ORDER BY sales_rank;