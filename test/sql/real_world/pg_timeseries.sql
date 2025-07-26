-- name: aggregate_timeseries
-- 時系列データの集計（実使用例）
WITH time_buckets AS (
  SELECT 
    date_trunc(:interval::interval, timestamp) as bucket,
    AVG(value)::numeric(10,2) as avg_value,
    MIN(value)::numeric(10,2) as min_value,
    MAX(value)::numeric(10,2) as max_value,
    COUNT(*)::integer as data_points
  FROM timeseries
  WHERE 
    timestamp BETWEEN :start_time::timestamptz AND :end_time::timestamptz
    AND metadata->>'sensor' = :sensor::text
  GROUP BY bucket
)
SELECT 
  bucket,
  extract(hour from bucket)::integer as hour,
  avg_value,
  min_value,
  max_value,
  data_points,
  -- 移動平均の計算
  AVG(avg_value) OVER (
    ORDER BY bucket 
    ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
  )::numeric(10,2) as moving_avg
FROM time_buckets
ORDER BY bucket