# Ectoストリーミングガイド

## 概要

YesqlのEctoストリーミング機能を使用すると、Ecto.Repo.streamを活用して大規模データセットを効率的に処理できます。

## 基本的な使い方

### セットアップ

```elixir
# SQLファイル: priv/sql/users/active_users.sql
-- name: get_active_users
-- 活発なユーザーを取得
SELECT * FROM users 
WHERE last_login > :since
  AND status = 'active'
ORDER BY id
```

```elixir
defmodule MyApp.Queries do
  use Yesql, driver: :ecto
  
  Yesql.defquery("priv/sql/users/active_users.sql")
end
```

### トランザクション内でのストリーミング

Ecto.Repo.streamはトランザクション内でのみ動作します：

```elixir
MyApp.Repo.transaction(fn ->
  {:ok, stream} = Yesql.Stream.query(
    MyApp.Repo,
    "SELECT * FROM large_table WHERE created_at > $1",
    [~D[2024-01-01]],
    driver: :ecto,
    max_rows: 1000  # 一度に取得する行数
  )
  
  stream
  |> Stream.map(&process_row/1)
  |> Stream.each(&save_result/1)
  |> Stream.run()
end)
```

## 高度な使用例

### バッチ処理

大量のデータを一定のサイズでバッチ処理：

```elixir
{:ok, batch_count} = Yesql.Stream.batch_process(
  MyApp.Repo,
  "SELECT * FROM orders WHERE status = $1",
  ["pending"],
  100,  # バッチサイズ
  fn batch ->
    # 100件ずつ処理
    Enum.each(batch, &process_order/1)
  end,
  driver: :ecto
)

IO.puts("処理したバッチ数: #{batch_count}")
```

### カーソルベースストリーミング（トランザクション不要）

長時間実行されるジョブで、トランザクションを使いたくない場合：

```elixir
stream = Yesql.Stream.EctoStream.cursor_based_stream(
  MyApp.Repo,
  "SELECT * FROM events WHERE processed = false",
  [],
  :id,  # カーソルとして使用するカラム
  chunk_size: 500
)

stream
|> Stream.each(fn event ->
  process_event(event)
  mark_as_processed(event.id)
end)
|> Stream.run()
```

### 並列処理

複数のワーカーでデータを並列処理：

```elixir
MyApp.Repo.transaction(fn ->
  {:ok, stream} = Yesql.Stream.EctoStream.parallel_stream(
    MyApp.Repo,
    "SELECT * FROM large_dataset",
    [],
    parallelism: System.schedulers_online(),
    chunk_size: 1000
  )
  
  stream
  |> Stream.each(&heavy_computation/1)
  |> Stream.run()
end)
```

## 実践的な例

### CSVエクスポート

```elixir
defmodule MyApp.DataExport do
  def export_users_to_csv(filename) do
    file = File.open!(filename, [:write, :utf8])
    
    # ヘッダーを書き込み
    IO.write(file, "id,name,email,created_at\n")
    
    MyApp.Repo.transaction(fn ->
      {:ok, count} = Yesql.Stream.process(
        MyApp.Repo,
        "SELECT id, name, email, created_at FROM users ORDER BY id",
        [],
        fn user ->
          csv_line = [
            user.id,
            escape_csv(user.name),
            user.email,
            user.created_at
          ] |> Enum.join(",")
          
          IO.write(file, csv_line <> "\n")
        end,
        driver: :ecto,
        max_rows: 5000
      )
      
      IO.puts("エクスポート完了: #{count}件")
      count
    end)
    
    File.close(file)
  end
  
  defp escape_csv(value) when is_binary(value) do
    if String.contains?(value, [",", "\"", "\n"]) do
      "\"" <> String.replace(value, "\"", "\"\"") <> "\""
    else
      value
    end
  end
  
  defp escape_csv(value), do: to_string(value)
end
```

### データ移行

```elixir
defmodule MyApp.DataMigration do
  def migrate_legacy_data do
    MyApp.Repo.transaction(fn ->
      # レガシーデータを新しい形式に移行
      {:ok, migrated} = Yesql.Stream.reduce(
        MyApp.Repo,
        """
        SELECT * FROM legacy_users 
        WHERE migrated = false
        ORDER BY id
        """,
        [],
        0,
        fn legacy_user, count ->
          case create_new_user(legacy_user) do
            {:ok, _} -> 
              mark_as_migrated(legacy_user.id)
              count + 1
            {:error, reason} ->
              Logger.error("移行失敗: #{legacy_user.id} - #{inspect(reason)}")
              count
          end
        end,
        driver: :ecto,
        max_rows: 100
      )
      
      Logger.info("移行完了: #{migrated}件")
      migrated
    end,
    timeout: :infinity,  # 長時間のトランザクション
    isolation: :read_committed
  )
  end
end
```

### 集計処理

```elixir
defmodule MyApp.Analytics do
  def calculate_monthly_revenue(year, month) do
    MyApp.Repo.transaction(fn ->
      {:ok, total} = Yesql.Stream.reduce(
        MyApp.Repo,
        """
        SELECT amount, tax, discount
        FROM orders
        WHERE EXTRACT(YEAR FROM created_at) = $1
          AND EXTRACT(MONTH FROM created_at) = $2
          AND status = 'completed'
        """,
        [year, month],
        Decimal.new(0),
        fn order, acc ->
          net_amount = order.amount
          |> Decimal.sub(order.discount)
          |> Decimal.add(order.tax)
          
          Decimal.add(acc, net_amount)
        end,
        driver: :ecto
      )
      
      total
    end)
  end
end
```

## パフォーマンス考慮事項

### max_rowsの設定

- デフォルトは500行
- メモリ使用量とパフォーマンスのバランスを考慮
- 大きすぎるとメモリを消費、小さすぎるとクエリ回数が増加

```elixir
# 小さいレコード（IDのリストなど）
{:ok, stream} = Yesql.Stream.query(repo, sql, params, 
  driver: :ecto, 
  max_rows: 10_000
)

# 大きいレコード（BLOBやJSONを含む）
{:ok, stream} = Yesql.Stream.query(repo, sql, params, 
  driver: :ecto, 
  max_rows: 100
)
```

### トランザクションタイムアウト

長時間のストリーミング処理では、タイムアウトの設定が重要：

```elixir
MyApp.Repo.transaction(
  fn ->
    # ストリーミング処理
  end,
  timeout: :infinity,  # または具体的なミリ秒数
  isolation: :read_committed  # 分離レベル
)
```

### メモリ管理

```elixir
# メモリ効率的な処理
MyApp.Repo.transaction(fn ->
  Yesql.Stream.process(
    MyApp.Repo,
    "SELECT * FROM huge_table",
    [],
    fn row ->
      # 行ごとに処理し、結果を蓄積しない
      send_to_external_service(row)
      :ok  # メモリに保持しない
    end,
    driver: :ecto,
    max_rows: 1000
  )
end)
```

## トラブルシューティング

### "not inside transaction"エラー

```elixir
# ❌ 間違い
{:ok, stream} = Yesql.Stream.query(MyApp.Repo, sql, params, driver: :ecto)
Enum.to_list(stream)  # エラー！

# ✅ 正しい
MyApp.Repo.transaction(fn ->
  {:ok, stream} = Yesql.Stream.query(MyApp.Repo, sql, params, driver: :ecto)
  Enum.to_list(stream)
end)
```

### タイムアウトエラー

```elixir
# 長時間の処理にはタイムアウトを調整
MyApp.Repo.transaction(
  fn -> 
    # ストリーミング処理
  end,
  timeout: 60_000 * 30  # 30分
)
```

### メモリ不足

カーソルベースストリーミングを使用：

```elixir
# トランザクションを使わず、メモリ効率的に処理
Yesql.Stream.EctoStream.cursor_based_stream(
  MyApp.Repo,
  sql,
  params,
  :id,
  chunk_size: 100
)
|> Stream.each(&process/1)
|> Stream.run()
```

## まとめ

EctoストリーミングはYesqlの他のドライバーと同じインターフェースで使用でき、Ectoの強力な機能を活用しながら大規模データセットを効率的に処理できます。トランザクション管理、エラーハンドリング、パフォーマンスチューニングに注意を払うことで、安定した高性能なデータ処理が可能になります。