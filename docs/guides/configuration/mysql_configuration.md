# MySQL/MariaDB設定

このガイドでは、YesqlでMySQL/MariaDBドライバーを使用する方法を説明します。

## インストール

`mix.exs`に以下の依存関係を追加してください：

```elixir
defp deps do
  [
    {:yesql, "~> 2.0"},
    {:myxql, "~> 0.6"}
  ]
end
```

## 基本的な使用方法

```elixir
defmodule MyApp.Queries do
  use Yesql, driver: :mysql
  
  Yesql.defquery("queries/users.sql")
end
```

## 接続の設定

### 基本的な接続

```elixir
{:ok, conn} = MyXQL.start_link(
  hostname: "localhost",
  port: 3306,
  username: "root",
  password: "password",
  database: "myapp_db"
)
```

### 接続プールの使用

本番環境では、接続プールの使用を推奨します：

```elixir
defmodule MyApp.MySQLPool do
  use GenServer
  
  def start_link(opts) do
    config = [
      name: {:local, __MODULE__},
      hostname: "localhost",
      username: "root",
      password: "password",
      database: "myapp_db",
      pool_size: 10
    ]
    
    MyXQL.start_link(config)
  end
end

# アプリケーションのスーパーバイザーに追加
children = [
  MyApp.MySQLPool,
  # 他の子プロセス...
]
```

## SQLファイルの作成

MySQLは位置パラメータ（`?`）を使用しますが、Yesqlでは名前付きパラメータを使用できます：

```sql
-- queries/get_user.sql
-- name: get_user
SELECT * FROM users WHERE id = :id;

-- queries/search_users.sql  
-- name: search_users
SELECT * FROM users 
WHERE name LIKE :name_pattern
  AND age >= :min_age
ORDER BY created_at DESC
LIMIT :limit;
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

YesqlのMySQLドライバーは、名前付きパラメータを自動的にMySQLの位置パラメータに変換します：

- 入力: `:name`, `:age`
- 出力: `?`, `?`

パラメータは、SQLクエリ内での**出現順序**に基づいて配置されます。

## 結果の形式

MySQLドライバーは結果をマップのリストとして返します：

```elixir
{:ok, [
  %{id: 1, name: "Alice", age: 25},
  %{id: 2, name: "Bob", age: 30}
]}
```

## トランザクション

MyXQLのトランザクション機能を使用できます：

```elixir
MyXQL.transaction(conn, fn conn ->
  with {:ok, _} <- MyApp.Queries.insert_user(conn, name: "Alice", age: 25),
       {:ok, _} <- MyApp.Queries.update_balance(conn, user_id: 1, amount: 100) do
    :ok
  else
    {:error, reason} -> MyXQL.rollback(conn, reason)
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
    
  {:error, %MyXQL.Error{} = error} ->
    # データベースエラー
    Logger.error("Database error: #{inspect(error)}")
    {:error, :database_error}
end
```

## パフォーマンスのヒント

1. **プリペアドステートメント**: MyXQLは自動的にプリペアドステートメントを使用します
2. **接続プール**: 本番環境では必ず接続プールを使用してください
3. **バッチ操作**: 大量のデータを扱う場合は、バッチ処理を検討してください

## 注意事項

- MySQLの予約語（`order`, `group`など）をカラム名として使用する場合は、バッククォートで囲む必要があります
- 日時型は自動的にElixirの`DateTime`構造体に変換されます
- `NULL`値は`nil`として返されます

## トラブルシューティング

### 接続エラー

```elixir
{:error, :econnrefused}
```

MySQLサーバーが起動していることを確認してください。

### 認証エラー

```elixir
{:error, :invalid_password}
```

ユーザー名とパスワードが正しいことを確認してください。

### 文字エンコーディング

UTF-8を使用する場合は、接続オプションで指定してください：

```elixir
{:ok, conn} = MyXQL.start_link(
  # 他のオプション...
  charset: "utf8mb4"
)