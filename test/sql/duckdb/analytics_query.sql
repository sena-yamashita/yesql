SELECT 
  product,
  SUM(amount) as total_amount,
  SUM(quantity) as total_quantity,
  AVG(amount) as avg_amount
FROM sales
WHERE date BETWEEN :start_date AND :end_date
GROUP BY product
ORDER BY product