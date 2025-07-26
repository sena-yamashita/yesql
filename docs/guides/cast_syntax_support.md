# データベースキャスト構文のサポート

Yesqlは各データベースのキャスト構文を完全にサポートしています。

## PostgreSQL / DuckDB - :: キャスト構文

PostgreSQLとDuckDBは `::type` 形式のキャスト構文をサポートします：

```sql
-- name: search_with_cast
SELECT * FROM users 
WHERE data @> :filter::jsonb
  AND created_at > :date::timestamptz
  AND age > :min_age::integer
```

```elixir
MyQueries.search_with_cast(conn,
  filter: %{"active" => true},
  date: ~U[2024-01-01 00:00:00Z],
  min_age: 18
)
```

### サポートされるキャスト例

- `::text` - テキスト型へのキャスト
- `::integer` / `::int` - 整数型へのキャスト
- `::numeric(10,2)` - 精度指定付き数値型
- `::jsonb` / `::json` - JSON型へのキャスト
- `::timestamptz` / `::timestamp` - タイムスタンプ型
- `::date` / `::time` - 日付・時刻型
- `::uuid` - UUID型
- `::text[]` / `::integer[]` - 配列型
- `::custom_enum` - カスタム列挙型

## MySQL / SQLite / Oracle - CAST関数

これらのデータベースは標準SQLの `CAST()` 関数を使用します：

```sql
-- name: search_with_cast
SELECT * FROM users 
WHERE age > CAST(:min_age AS SIGNED)
  AND created_at > CAST(:date AS DATE)
```

## MSSQL - CAST/CONVERT関数

MSSQLは `CAST()` と `CONVERT()` の両方をサポートします：

```sql
-- name: search_with_cast
SELECT * FROM users 
WHERE age > CAST(:min_age AS INT)
  AND created_at > CONVERT(DATETIME, :date, 101)
```

## 注意事項

### パラメータ名の制限

Yesqlは `:` で始まる文字列をパラメータとして認識します。以下の点に注意してください：

1. **有効なパラメータ名**：
   - `:user_name` - アンダースコア可
   - `:userId` - キャメルケース可
   - `:value123` - 数字を含む可
   - `:@special` - 一部の特殊文字も可（ただし推奨しません）

2. **無効なパラメータ名**：
   - `: ` - 空のパラメータ名（エラー）
   - `: name` - スペースを含む（エラー）

### 文字列リテラル内のキャスト

SQLの文字列リテラル内の `::` はキャストとして解釈されません：

```sql
-- 正しく動作します
SELECT 'This is a string with :: in it' as message,
       :value::text as casted_value
```

### パフォーマンス

キャスト構文の使用はパース性能に影響しません。Yesqlのトークナイザーは `::` を特別に処理し、効率的にパラメータとキャストを区別します。

## トラブルシューティング

### "illegal" エラー

以下のようなエラーが発生した場合：

```
{:error, {1, Yesql.Tokenizer, {:illegal, ": "}}, 1}
```

これは無効なパラメータ構文（通常は `:` の後に空白）が原因です。パラメータ名を確認してください。

### キャストが認識されない

もし `::type` がパラメータとして誤認識される場合は、Yesqlのバージョンを確認してください。v2.0.0以降では、キャスト構文は完全にサポートされています。

## 実例

### PostgreSQL JSONB検索

```sql
-- name: find_users_by_criteria
WITH filtered_users AS (
  SELECT * FROM users 
  WHERE data @> :must_have::jsonb
    AND NOT (data @> :must_not_have::jsonb)
    AND (data->>'age')::integer BETWEEN :min_age::integer AND :max_age::integer
)
SELECT 
  id,
  data->>'name' as name,
  (data->>'score')::numeric as score
FROM filtered_users
WHERE (data->'tags')::jsonb ?| :any_tags::text[]
ORDER BY score DESC
```

### DuckDB分析クエリ

```sql
-- name: analyze_time_series  
SELECT 
  date_trunc('hour', timestamp)::timestamp as hour,
  percentile_cont(0.5) WITHIN GROUP (ORDER BY value)::numeric as median,
  percentile_cont(0.95) WITHIN GROUP (ORDER BY value)::numeric as p95
FROM measurements
WHERE timestamp BETWEEN :start::timestamp AND :end::timestamp
  AND sensor_id = ANY(:sensors::integer[])
GROUP BY hour
```

このようにYesqlは、各データベースのネイティブなキャスト構文を完全にサポートし、型安全性を保ちながら柔軟なクエリ記述を可能にします。