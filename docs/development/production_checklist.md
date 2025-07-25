# 本番環境チェックリスト

YesQLを本番環境で使用する際のチェックリストです。

## 1. 依存関係の確認

### 必須の依存関係

```elixir
# mix.exs
defp deps do
  [
    {:yesql, "~> 2.0"},
    # 使用するドライバーを追加（optionalフラグを外す）
    {:postgrex, "~> 0.15"},     # PostgreSQL
    {:myxql, "~> 0.6"},         # MySQL
    {:tds, "~> 2.3"},           # MSSQL
    {:jamdb_oracle, "~> 0.5"},  # Oracle
    {:duckdbex, "~> 0.3.9"}     # DuckDB
  ]
end
```

### バージョン固定

本番環境では正確なバージョンを指定することを推奨：

```elixir
{:yesql, "2.0.0"},
{:postgrex, "0.17.3"}
```

## 2. 接続プールの設定

### PostgreSQLの例

```elixir
# config/prod.exs
config :my_app, MyApp.Repo,
  adapter: Ecto.Adapters.Postgres,
  pool_size: 20,  # 本番環境では大きめに
  pool_timeout: 15_000,
  timeout: 15_000,
  queue_target: 5_000,
  queue_interval: 1_000
```

### MySQLの例

```elixir
# 接続プールの設定
defmodule MyApp.DatabasePool do
  use Supervisor
  
  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(_opts) do
    pool_config = [
      name: {:local, :mysql_pool},
      worker_module: MyXQL,
      size: 20,
      max_overflow: 10
    ]
    
    worker_config = [
      hostname: System.get_env("MYSQL_HOST"),
      username: System.get_env("MYSQL_USER"),
      password: System.get_env("MYSQL_PASSWORD"),
      database: System.get_env("MYSQL_DATABASE"),
      ssl: true,
      prepare: :named,
      timeout: 15_000
    ]
    
    children = [
      :poolboy.child_spec(:mysql_pool, pool_config, worker_config)
    ]
    
    Supervisor.init(children, strategy: :one_for_one)
  end
end
```

## 3. エラーハンドリング

### タイムアウト処理

```elixir
defmodule MyApp.SafeQueries do
  use Yesql, driver: :postgrex
  
  Yesql.defquery("queries/important_query.sql")
  
  def safe_important_query(conn, params) do
    task = Task.async(fn ->
      important_query(conn, params)
    end)
    
    case Task.yield(task, 30_000) || Task.shutdown(task) do
      {:ok, result} -> result
      nil -> {:error, :timeout}
    end
  end
end
```

### リトライロジック

```elixir
defmodule MyApp.ResilientQueries do
  require Logger
  
  def with_retry(fun, opts \\ []) do
    max_attempts = Keyword.get(opts, :max_attempts, 3)
    delay = Keyword.get(opts, :delay, 1000)
    
    do_with_retry(fun, max_attempts, delay, 0)
  end
  
  defp do_with_retry(fun, max_attempts, delay, attempt) do
    case fun.() do
      {:ok, _} = result ->
        result
        
      {:error, %{postgres: %{code: :connection_exception}}} when attempt < max_attempts ->
        Logger.warn("Database connection error, retrying in #{delay}ms...")
        Process.sleep(delay)
        do_with_retry(fun, max_attempts, delay * 2, attempt + 1)
        
      {:error, _} = error ->
        error
    end
  end
end
```

## 4. パフォーマンス最適化

### クエリの最適化

```sql
-- queries/optimized_user_search.sql
-- name: search_users_optimized
-- インデックスヒントを使用（MySQL）
SELECT /*+ INDEX(users idx_users_status_created) */
  id, name, email, status
FROM users
WHERE status = :status
  AND created_at > :since
ORDER BY created_at DESC
LIMIT :limit;
```

### プリペアドステートメントの活用

```elixir
# PostgreSQLでの名前付きプリペアドステートメント
defmodule MyApp.PreparedQueries do
  def prepare_statements(conn) do
    Postgrex.prepare(conn, "get_user", "SELECT * FROM users WHERE id = $1")
    Postgrex.prepare(conn, "get_orders", "SELECT * FROM orders WHERE user_id = $1 AND status = $2")
  end
  
  def get_user_with_prepared(conn, user_id) do
    Postgrex.execute(conn, "get_user", [user_id])
  end
end
```

## 5. セキュリティ

### SQLインジェクション対策

YesQLは自動的にパラメータをサニタイズしますが、以下の点に注意：

```elixir
# NG: 動的なテーブル名は危険
def bad_query(table_name) do
  # SQLインジェクションの危険性
  Postgrex.query(conn, "SELECT * FROM #{table_name}", [])
end

# OK: ホワイトリスト方式
def good_query(table_type) do
  table_name = case table_type do
    :users -> "users"
    :orders -> "orders"
    _ -> raise "Invalid table type"
  end
  
  Postgrex.query(conn, "SELECT * FROM #{table_name}", [])
end
```

### 接続の暗号化

```elixir
# SSL/TLS接続の設定
{:ok, conn} = Postgrex.start_link(
  hostname: "production.db.example.com",
  username: System.get_env("DB_USER"),
  password: System.get_env("DB_PASSWORD"),
  database: "production_db",
  ssl: true,
  ssl_opts: [
    cacertfile: "/path/to/ca-cert.pem",
    verify: :verify_peer,
    server_name_indication: 'production.db.example.com'
  ]
)
```

## 6. 監視とロギング

### クエリのロギング

```elixir
defmodule MyApp.LoggedQueries do
  use Yesql, driver: :postgrex
  require Logger
  
  Yesql.defquery("queries/user_query.sql")
  
  def logged_user_query(conn, params) do
    start_time = System.monotonic_time()
    
    result = user_query(conn, params)
    
    duration = System.monotonic_time() - start_time
    duration_ms = System.convert_time_unit(duration, :native, :millisecond)
    
    Logger.info("Query executed",
      query: "user_query",
      duration_ms: duration_ms,
      params: inspect(params, limit: :infinity)
    )
    
    result
  end
end
```

### メトリクス収集

```elixir
defmodule MyApp.MetricQueries do
  use Yesql, driver: :postgrex
  
  def with_metrics(query_name, fun) do
    start_time = System.monotonic_time()
    
    try do
      result = fun.()
      
      :telemetry.execute(
        [:yesql, :query, :success],
        %{duration: System.monotonic_time() - start_time},
        %{query: query_name}
      )
      
      result
    rescue
      error ->
        :telemetry.execute(
          [:yesql, :query, :error],
          %{duration: System.monotonic_time() - start_time},
          %{query: query_name, error: error}
        )
        
        reraise error, __STACKTRACE__
    end
  end
end
```

## 7. デプロイメント

### ヘルスチェック

```elixir
defmodule MyApp.HealthCheck do
  use Yesql, driver: :postgrex
  
  # queries/health_check.sql
  # -- name: health_check
  # SELECT 1 as status;
  Yesql.defquery("queries/health_check.sql")
  
  def check_database(conn) do
    case health_check(conn) do
      {:ok, [%{status: 1}]} -> :ok
      _ -> :error
    end
  end
end
```

### グレースフルシャットダウン

```elixir
defmodule MyApp.Application do
  use Application
  
  def stop(_state) do
    # 接続プールを適切にシャットダウン
    Supervisor.stop(MyApp.DatabasePool, :shutdown)
  end
end
```

## 8. トラブルシューティング

### よくある問題と対策

1. **接続プールの枯渇**
   - pool_sizeを増やす
   - クエリのタイムアウトを設定
   - 長時間実行クエリを最適化

2. **メモリリーク**
   - 大量のデータを扱う場合はストリーミングを検討
   - 結果セットのサイズを制限

3. **デッドロック**
   - トランザクションの順序を統一
   - トランザクションの範囲を最小限に

### デバッグ設定

```elixir
# config/prod.exs
config :logger, level: :info

# クエリのデバッグが必要な場合
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:query, :duration_ms]
```

## チェックリスト

本番デプロイ前に以下を確認：

- [ ] 適切な接続プールサイズの設定
- [ ] SSL/TLS接続の有効化
- [ ] エラーハンドリングの実装
- [ ] タイムアウトの設定
- [ ] ロギングとメトリクスの設定
- [ ] ヘルスチェックの実装
- [ ] 環境変数での認証情報管理
- [ ] インデックスの最適化
- [ ] クエリのパフォーマンステスト完了
- [ ] バックアップとリカバリ手順の確立