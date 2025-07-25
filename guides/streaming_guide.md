# ストリーミング結果セットガイド

このガイドでは、YesQLのストリーミング機能を使用して大量のデータを効率的に処理する方法を説明します。

## 概要

ストリーミング結果セットは、大量のデータを扱う際にメモリ使用量を最小限に抑えながら、データを順次処理する機能です。通常のクエリ実行では全ての結果をメモリに読み込みますが、ストリーミングでは必要な分だけをチャンクごとに処理します。

### 利点

- **メモリ効率**: 大規模なデータセットでもメモリ使用量が一定
- **レスポンス性**: 最初の結果をすぐに処理開始できる
- **スケーラビリティ**: データ量に関わらず安定した性能
- **柔軟性**: Elixir Streamとの統合により、様々な処理パターンに対応

## 基本的な使用方法

### シンプルなストリーミング

```elixir
alias Yesql.Stream

# 100万件のデータをストリーミング処理
{:ok, stream} = Stream.query(conn,
  "SELECT * FROM large_table WHERE created_at > $1",
  [~D[2024-01-01]],
  driver: :postgrex,
  chunk_size: 1000
)

# ストリームを処理
stream
|> Stream.map(fn row ->
  # 各行を処理
  process_row(row)
end)
|> Stream.filter(&valid?/1)
|> Enum.to_list()
```

### データ処理

```elixir
# ファイルへのエクスポート
{:ok, count} = Stream.process(conn,
  "SELECT * FROM users WHERE status = $1",
  ["active"],
  fn row ->
    csv_line = [row.id, row.name, row.email] |> Enum.join(",")
    File.write!("users.csv", csv_line <> "\n", [:append])
  end,
  driver: :postgrex,
  chunk_size: 5000
)

IO.puts("Exported #{count} users")
```

### 集約処理

```elixir
# 売上合計を計算（メモリ効率的）
{:ok, total} = Stream.reduce(conn,
  "SELECT amount FROM sales WHERE year = $1",
  [2024],
  0,
  fn row, acc -> acc + row.amount end,
  driver: :mysql
)

IO.puts("Total sales: #{total}")
```

### バッチ処理

```elixir
# 1000件ずつバッチ処理
{:ok, batch_count} = Stream.batch_process(conn,
  "SELECT * FROM logs WHERE level = $1",
  ["error"],
  1000,  # バッチサイズ
  fn batch ->
    # バッチごとに外部APIに送信
    ExternalAPI.bulk_send(batch)
  end,
  driver: :postgrex
)
```

## ドライバー別の特徴

### PostgreSQL

PostgreSQLは最も高度なストリーミング機能を提供します：

```elixir
alias Yesql.Stream.PostgrexStream

# カーソルベースのストリーミング
{:ok, stream} = PostgrexStream.create(conn,
  "SELECT * FROM large_table",
  [],
  max_rows: 5000
)

# 非同期ストリーミング
{:ok, async_stream} = PostgrexStream.create_async(conn,
  "SELECT * FROM analytics_data",
  [],
  max_rows: 10000
)

# 統計情報付きストリーミング
{result, stats} = PostgrexStream.with_stats(conn,
  "SELECT * FROM events",
  [],
  fn row -> process_event(row) end
)

IO.inspect(stats)
# %{
#   row_count: 1000000,
#   chunk_count: 200,
#   duration_ms: 45000,
#   memory_used: 10485760,
#   rows_per_second: 22222.22
# }
```

### MySQL

MySQLのサーバーサイドカーソルを活用：

```elixir
alias Yesql.Stream.MySQLStream

# サーバーサイドカーソル
{:ok, stream} = MySQLStream.create_with_cursor(conn,
  "SELECT * FROM products WHERE category = ?",
  ["electronics"],
  max_rows: 1000
)

# ファイルへの直接エクスポート
{:ok, count} = MySQLStream.export_to_file(conn,
  "SELECT * FROM orders",
  [],
  "orders.csv",
  format: :csv,
  include_headers: true
)

# パラレルストリーミング（パーティション使用）
{:ok, stream} = MySQLStream.create_parallel_partitioned(
  [conn1, conn2, conn3, conn4],  # 複数の接続
  "users",
  "SELECT * FROM users WHERE active = ?",
  [true],
  partition_key: :id
)
```

### DuckDB

分析用途に最適化されたストリーミング：

```elixir
alias Yesql.Stream.DuckDBStream

# 基本的なストリーミング
{:ok, stream} = DuckDBStream.create(conn,
  "SELECT * FROM fact_sales",
  [],
  chunk_size: 10000,
  prefetch: true
)

# Parquetファイルへのエクスポート
{:ok, file} = DuckDBStream.export_to_parquet(conn,
  "SELECT * FROM analytics_table",
  [],
  "output.parquet",
  compression: :snappy,
  row_group_size: 100000
)

# 並列テーブルスキャン
{:ok, stream} = DuckDBStream.create_parallel_scan(conn,
  "large_table",
  parallelism: 8,
  where: "date >= '2024-01-01'"
)

# ウィンドウ付きストリーミング（時系列データ）
{:ok, windowed_stream} = DuckDBStream.create_windowed_stream(conn,
  "SELECT * FROM timeseries",
  [],
  "timestamp",  # ウィンドウ列
  3600,         # ウィンドウサイズ（秒）
  overlap: 300  # オーバーラップ（秒）
)
```

### SQLite

組み込みデータベースでの効率的なストリーミング：

```elixir
alias Yesql.Stream.SQLiteStream

# メモリ最適化ストリーミング
{:ok, stream} = SQLiteStream.create_memory_optimized(conn,
  "SELECT * FROM local_data",
  [],
  chunk_size: 500
)

# インデックスを活用した高速ストリーミング
{:ok, stream} = SQLiteStream.create_indexed_stream(conn,
  "users",
  "created_at",  # インデックス列
  start_value: "2024-01-01",
  end_value: "2024-12-31"
)

# FTS5（全文検索）ストリーミング
{:ok, stream} = SQLiteStream.create_fts_stream(conn,
  "documents",
  "important keywords",
  rank_order: true
)

# バッチ挿入
{:ok, count} = SQLiteStream.stream_insert(conn,
  "events",
  [:type, :data, :timestamp],
  event_stream,  # 既存のストリーム
  batch_size: 1000
)
```

## パフォーマンス最適化

### チャンクサイズの調整

```elixir
# 小さなチャンク（低メモリ、多いラウンドトリップ）
{:ok, stream} = Stream.query(conn, sql, params,
  driver: :postgrex,
  chunk_size: 100
)

# 大きなチャンク（高メモリ、少ないラウンドトリップ）
{:ok, stream} = Stream.query(conn, sql, params,
  driver: :postgrex,
  chunk_size: 10000
)
```

### 並列処理

```elixir
# 複数のストリームを並列処理
streams = 1..4
|> Enum.map(fn i ->
  Task.async(fn ->
    {:ok, stream} = Stream.query(conn,
      "SELECT * FROM data WHERE partition = $1",
      [i],
      driver: :postgrex
    )
    
    stream
    |> Stream.map(&process/1)
    |> Enum.to_list()
  end)
end)

results = Task.await_many(streams, :infinity)
```

### メモリプロファイリング

```elixir
# メモリ使用量を監視しながらストリーミング
initial_memory = :erlang.memory(:total)

{:ok, _} = Stream.process(conn, sql, params,
  fn row ->
    current_memory = :erlang.memory(:total)
    if current_memory - initial_memory > 100_000_000 do
      IO.warn("Memory usage exceeded 100MB")
    end
    
    process_row(row)
  end,
  driver: :postgrex
)
```

## エラーハンドリング

### 接続エラー

```elixir
case Stream.query(conn, sql, params, driver: :mysql) do
  {:ok, stream} ->
    process_stream(stream)
    
  {:error, %MyXQL.Error{} = error} ->
    Logger.error("Database error: #{inspect(error)}")
    {:error, :database_error}
    
  {:error, :streaming_not_supported} ->
    # フォールバック: 通常のクエリを使用
    fallback_query(conn, sql, params)
end
```

### ストリーム処理中のエラー

```elixir
{:ok, stream} = Stream.query(conn, sql, params, driver: :postgrex)

try do
  stream
  |> Stream.map(fn row ->
    case process_row(row) do
      {:ok, result} -> result
      {:error, reason} -> throw({:processing_error, row.id, reason})
    end
  end)
  |> Enum.to_list()
catch
  {:processing_error, id, reason} ->
    Logger.error("Failed to process row #{id}: #{inspect(reason)}")
    {:error, {:processing_failed, id}}
end
```

## ベストプラクティス

### 1. 適切なチャンクサイズの選択

- **ネットワーク遅延が高い場合**: 大きなチャンク（5000-10000）
- **メモリが制限されている場合**: 小さなチャンク（100-1000）
- **リアルタイム処理**: 非常に小さなチャンク（10-100）

### 2. タイムアウトの設定

```elixir
{:ok, stream} = Stream.query(conn, sql, params,
  driver: :postgrex,
  chunk_size: 1000,
  timeout: 300_000  # 5分
)
```

### 3. リソースのクリーンアップ

```elixir
# try/afterを使用してリソースを確実に解放
try do
  {:ok, stream} = Stream.query(conn, sql, params, driver: :sqlite)
  process_stream(stream)
after
  # 接続プールに接続を返却
  GenServer.cast(conn, :checkin)
end
```

### 4. 進捗状況の追跡

```elixir
{:ok, total_count} = get_total_count(conn)
processed = 0

{:ok, _} = Stream.process(conn, sql, params,
  fn row ->
    processed = processed + 1
    
    if rem(processed, 1000) == 0 do
      progress = (processed / total_count * 100) |> Float.round(2)
      IO.write("\rProgress: #{progress}%")
    end
    
    process_row(row)
  end,
  driver: :postgrex
)
```

## トラブルシューティング

### メモリ不足

症状: プロセスがクラッシュまたは極端に遅くなる

解決策:
- チャンクサイズを小さくする
- `Stream.process`を使用して結果を蓄積しない
- 並列処理を減らす

### タイムアウト

症状: `:timeout`エラー

解決策:
- クエリの最適化（インデックスの追加）
- タイムアウト値を増やす
- より小さなデータセットに分割

### 接続プールの枯渇

症状: 接続を取得できない

解決策:
- ストリーミング完了後に接続を解放
- プールサイズを増やす
- 並列ストリームの数を制限

## まとめ

YesQLのストリーミング機能は、大規模なデータセットを効率的に処理するための強力なツールです。各データベースドライバーの特性を理解し、適切なオプションを選択することで、メモリ効率とパフォーマンスのバランスを最適化できます。