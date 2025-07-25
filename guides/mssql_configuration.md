# MSSQL（SQL Server）設定

このガイドでは、YesqlでMSSQLドライバーを使用する方法を説明します。

## インストール

`mix.exs`に以下の依存関係を追加してください：

```elixir
defp deps do
  [
    {:yesql, "~> 2.0"},
    {:tds, "~> 2.3"}
  ]
end
```

## 基本的な使用方法

```elixir
defmodule MyApp.Queries do
  use Yesql, driver: :mssql
  
  Yesql.defquery("queries/users.sql")
end
```

## 接続の設定

### 基本的な接続

```elixir
{:ok, conn} = Tds.start_link(
  hostname: "localhost",
  port: 1433,
  username: "sa",
  password: "YourStrong!Passw0rd",
  database: "myapp_db",
  trust_server_certificate: true
)
```

### Azure SQL Databaseへの接続

```elixir
{:ok, conn} = Tds.start_link(
  hostname: "your-server.database.windows.net",
  port: 1433,
  username: "your-username",
  password: "your-password",
  database: "your-database",
  ssl: true
)
```

### 接続プールの使用

```elixir
defmodule MyApp.MSSQLPool do
  use GenServer
  
  def start_link(opts) do
    config = [
      name: {:local, __MODULE__},
      hostname: "localhost",
      username: "sa",
      password: "YourStrong!Passw0rd",
      database: "myapp_db",
      pool_size: 10,
      trust_server_certificate: true
    ]
    
    Tds.start_link(config)
  end
end
```

## SQLファイルの作成

MSSQLは名前付きパラメータ（`@p1`, `@p2`...）を使用しますが、Yesqlでは通常の名前付きパラメータを使用できます：

```sql
-- queries/get_user.sql
-- name: get_user
SELECT * FROM users WHERE id = :id;

-- queries/search_users.sql
-- name: search_users
SELECT TOP :limit * FROM users 
WHERE name LIKE :name_pattern
  AND age >= :min_age
ORDER BY created_at DESC;
```

## クエリの実行

```elixir
# 単一のパラメータ
{:ok, users} = MyApp.Queries.get_user(conn, id: 123)

# 複数のパラメータ
{:ok, results} = MyApp.Queries.search_users(conn,
  name_pattern: "%john%",
  min_age: 18,
  limit: 10
)
```

## パラメータ形式

YesqlのMSSQLドライバーは、名前付きパラメータを自動的にMSSQLの名前付きパラメータに変換します：

- 入力: `:name`, `:age`
- 出力: `@p1`, `@p2`...

パラメータは、SQLクエリ内での**出現順序**に基づいて番号付けされます。

## 結果の形式

MSSQLドライバーは結果をマップのリストとして返します：

```elixir
{:ok, [
  %{id: 1, name: "Alice", age: 25},
  %{id: 2, name: "Bob", age: 30}
]}
```

## トランザクション

Tdsのトランザクション機能を使用できます：

```elixir
Tds.transaction(conn, fn conn ->
  with {:ok, _} <- MyApp.Queries.insert_user(conn, name: "Alice", age: 25),
       {:ok, _} <- MyApp.Queries.update_balance(conn, user_id: 1, amount: 100) do
    :ok
  else
    {:error, reason} -> Tds.rollback(conn, reason)
  end
end)
```

## エラーハンドリング

```elixir
case MyApp.Queries.get_user(conn, id: user_id) do
  {:ok, [user]} -> 
    # ユーザーが見つかった
    {:ok, user}
    
  {:ok, []} -> 
    # ユーザーが見つからない
    {:error, :not_found}
    
  {:error, %Tds.Error{} = error} ->
    # データベースエラー
    Logger.error("Database error: #{inspect(error)}")
    {:error, :database_error}
end
```

## MSSQL固有の機能

### OUTPUT句の使用

```sql
-- queries/insert_user_with_id.sql
-- name: insert_user_with_id
INSERT INTO users (name, age)
OUTPUT INSERTED.id, INSERTED.created_at
VALUES (:name, :age);
```

### ストアドプロシージャの実行

```elixir
# ストアドプロシージャの呼び出し
{:ok, result} = Tds.query(conn, "EXEC GetUserById @p1", [user_id])
```

## パフォーマンスのヒント

1. **接続プール**: 本番環境では必ず接続プールを使用してください
2. **インデックス**: 適切なインデックスを作成してクエリパフォーマンスを向上させてください
3. **バッチ処理**: 大量のデータを扱う場合は、バッチ処理を検討してください

## 注意事項

- MSSQLの予約語（`user`, `order`など）をテーブル名やカラム名として使用する場合は、角括弧で囲む必要があります（`[user]`, `[order]`）
- 日時型は自動的にElixirの`DateTime`構造体に変換されます
- `NULL`値は`nil`として返されます
- Unicode文字列は`NVARCHAR`型を使用してください

## トラブルシューティング

### 接続エラー

```elixir
{:error, :econnrefused}
```

SQL Serverが起動していることと、TCP/IP接続が有効になっていることを確認してください。

### 認証エラー

```elixir
{:error, :invalid_credentials}
```

SQL Server認証が有効になっていることを確認し、ユーザー名とパスワードが正しいことを確認してください。

### SSL/TLS接続

開発環境でSSL証明書の検証をスキップする場合：

```elixir
{:ok, conn} = Tds.start_link(
  # 他のオプション...
  trust_server_certificate: true
)