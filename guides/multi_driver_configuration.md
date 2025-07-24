# マルチドライバー設定

Yesqlは柔軟なドライバー抽象化レイヤーを通じて、複数のデータベースドライバーをサポートします。このガイドでは、アプリケーションで異なるドライバーを設定して使用する方法を説明します。

## 利用可能なドライバー

- **Postgrex** - PostgreSQLデータベースドライバー
- **Ecto** - 任意のEctoリポジトリで動作
- **DuckDB** - OLAP用途の分析データベース

## 設定オプション

### モジュールレベルの設定

`use`マクロを使用してモジュールレベルでドライバーを設定します：

```elixir
defmodule MyApp.Queries do
  use Yesql, driver: :postgrex, conn: MyApp.ConnectionPool
  
  Yesql.defquery("queries/users.sql")
end
```

### クエリ毎の設定

特定のクエリに対してドライバーをオーバーライドできます：

```elixir
defmodule MyApp.Queries do
  use Yesql
  
  # PostgreSQLを使用
  Yesql.defquery("queries/users.sql", driver: :postgrex)
  
  # 分析用にDuckDBを使用
  Yesql.defquery("queries/analytics.sql", driver: :duckdb)
end
```

## ドライバー固有のセットアップ

### PostgreSQL (Postgrex)

```elixir
# アプリケーション起動時
{:ok, pid} = Postgrex.start_link(
  hostname: "localhost",
  database: "myapp_dev",
  username: "postgres",
  password: "postgres",
  pool_size: 10
)

# クエリモジュール内
defmodule MyApp.PostgresQueries do
  use Yesql, driver: :postgrex, conn: pid
  
  Yesql.defquery("queries/users.sql")
end
```

### Ectoリポジトリ

```elixir
defmodule MyApp.Queries do
  use Yesql, driver: :ecto, conn: MyApp.Repo
  
  Yesql.defquery("queries/users.sql")
end

# 使用方法
MyApp.Queries.users_by_country(country: "JPN")
```

### DuckDB

```elixir
# DuckDB接続のセットアップ
{:ok, db} = Duckdbex.open("analytics.duckdb")
{:ok, conn} = Duckdbex.connection(db)

defmodule MyApp.Analytics do
  use Yesql, driver: :duckdb
  
  Yesql.defquery("queries/revenue_report.sql")
end

# 使用方法
MyApp.Analytics.revenue_report(conn, year: 2024)
```

## パラメータ形式

異なるデータベースは異なるパラメータ形式を使用しますが、Yesqlは自動的に変換を処理します：

### SQLファイル（名前付きパラメータを使用）
```sql
-- queries/find_user.sql
SELECT * FROM users
WHERE email = :email
  AND active = :active
```

### ドライバーによって生成されるSQL
- **PostgreSQL/DuckDB**: `SELECT * FROM users WHERE email = $1 AND active = $2`
- **MySQL**（将来）: `SELECT * FROM users WHERE email = ? AND active = ?`

## 依存関係

必要なドライバー依存関係を`mix.exs`に追加します：

```elixir
defp deps do
  [
    # PostgreSQL用
    {:postgrex, "~> 0.15", optional: true},
    
    # Ecto用
    {:ecto, "~> 3.4", optional: true},
    {:ecto_sql, "~> 3.4", optional: true},
    
    # DuckDB用
    {:duckdbex, "~> 0.3.9", optional: true},
    
    # Yesql本体
    {:yesql, "~> 1.0"}
  ]
end
```

## 利用可能なドライバーの確認

実行時に利用可能なドライバーを確認できます：

```elixir
iex> Yesql.DriverFactory.available_drivers()
[:postgrex, :ecto, :duckdb]
```

## エラーハンドリング

読み込まれていないドライバーを使用しようとした場合：

```elixir
# DuckDBexが依存関係にない場合
defmodule MyApp.Queries do
  use Yesql, driver: :duckdb  # エラーが発生します
end
```

エラーメッセージ: `Driver duckdb is not loaded. Make sure the required library is in your dependencies.`

## 将来的なドライバー

ドライバーシステムは拡張可能に設計されています。将来のバージョンでは以下が含まれる可能性があります：

- MyXQL経由でのMySQL
- TDS経由でのMicrosoft SQL Server
- Oracle Database
- SQLite

カスタムドライバーを実装するには、`Yesql.Driver`プロトコルを実装するモジュールを作成してください。