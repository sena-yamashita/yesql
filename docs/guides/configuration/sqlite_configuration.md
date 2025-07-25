# SQLite設定

このガイドでは、YesqlでSQLiteドライバーを使用する方法を説明します。

## インストール

`mix.exs`に以下の依存関係を追加してください：

```elixir
defp deps do
  [
    {:yesql, "~> 2.0"},
    {:exqlite, "~> 0.13"}
  ]
end
```

## 基本的な使用方法

```elixir
defmodule MyApp.Queries do
  use Yesql, driver: :sqlite
  
  Yesql.defquery("queries/users.sql")
end
```

## 接続の設定

### ファイルベースのデータベース

```elixir
# 通常のファイルベースDB
{:ok, conn} = Exqlite.Sqlite3.open("myapp.db")

# 絶対パスも使用可能
{:ok, conn} = Exqlite.Sqlite3.open("/var/db/myapp.db")
```

### メモリデータベース

```elixir
# インメモリDB（テストや一時的なデータ処理に最適）
{:ok, conn} = Exqlite.Sqlite3.open(":memory:")
```

### 接続オプション

```elixir
# カスタムヘルパー関数を使用
{:ok, conn} = Yesql.Driver.SQLite.open("myapp.db",
  cache_size: 10000,      # キャッシュサイズ（ページ数）
  busy_timeout: 5000,     # ビジータイムアウト（ミリ秒）
  mode: :readwrite        # アクセスモード
)

# 読み取り専用モード
{:ok, conn} = Yesql.Driver.SQLite.open("myapp.db", mode: :readonly)
```

## SQLファイルの作成

SQLiteは`?`形式のプレースホルダーを使用しますが、Yesqlでは通常の名前付きパラメータを使用できます：

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

YesqlのSQLiteドライバーは、名前付きパラメータを自動的にSQLiteの`?`形式に変換します：

- 入力: `:name`, `:age`
- 出力: `?`, `?`

パラメータは、SQLクエリ内での**出現順序**に基づいて提供されます。

## 結果の形式

SQLiteドライバーは結果をマップのリストとして返します：

```elixir
{:ok, [
  %{id: 1, name: "Alice", age: 25, created_at: "2024-01-01 10:00:00"},
  %{id: 2, name: "Bob", age: 30, created_at: "2024-01-02 11:00:00"}
]}
```

## トランザクション

SQLiteのトランザクションは手動で管理する必要があります：

```elixir
# トランザクション開始
{:ok, _} = Exqlite.Sqlite3.execute(conn, "BEGIN TRANSACTION")

try do
  # 複数のクエリを実行
  {:ok, _} = MyApp.Queries.insert_user(conn, name: "Alice", age: 25)
  {:ok, _} = MyApp.Queries.update_balance(conn, user_id: 1, amount: 100)
  
  # コミット
  {:ok, _} = Exqlite.Sqlite3.execute(conn, "COMMIT")
rescue
  error ->
    # ロールバック
    {:ok, _} = Exqlite.Sqlite3.execute(conn, "ROLLBACK")
    reraise error, __STACKTRACE__
end
```

## SQLite固有の機能

### 全文検索（FTS5）

```sql
-- queries/create_fts_table.sql
-- name: create_fts_table
CREATE VIRTUAL TABLE documents USING fts5(
  title, 
  content, 
  tokenize = 'unicode61'
);

-- queries/search_documents.sql
-- name: search_documents
SELECT * FROM documents 
WHERE documents MATCH :search_query
ORDER BY rank;
```

### JSON操作

```sql
-- queries/json_operations.sql
-- name: extract_json_field
SELECT 
  id,
  json_extract(data, '$.name') as name,
  json_extract(data, '$.tags') as tags
FROM items
WHERE json_extract(data, '$.active') = true;
```

### ウィンドウ関数

```sql
-- queries/running_total.sql
-- name: calculate_running_total
SELECT 
  date,
  amount,
  SUM(amount) OVER (ORDER BY date) as running_total
FROM transactions
WHERE user_id = :user_id
ORDER BY date;
```

## パフォーマンス最適化

### インデックスの作成

```elixir
# インデックス作成
{:ok, _} = Exqlite.Sqlite3.execute(conn, """
  CREATE INDEX idx_users_email ON users(email);
""")

# 複合インデックス
{:ok, _} = Exqlite.Sqlite3.execute(conn, """
  CREATE INDEX idx_users_age_status ON users(age, status);
""")
```

### PRAGMA設定

```elixir
# パフォーマンス関連の設定
pragmas = [
  "PRAGMA journal_mode = WAL",           # Write-Ahead Logging
  "PRAGMA synchronous = NORMAL",         # 同期モード
  "PRAGMA cache_size = 10000",          # キャッシュサイズ
  "PRAGMA temp_store = MEMORY",         # 一時ストレージ
  "PRAGMA mmap_size = 30000000000"      # メモリマップサイズ
]

Enum.each(pragmas, fn pragma ->
  {:ok, _} = Exqlite.Sqlite3.execute(conn, pragma)
end)
```

### バッチ処理

```elixir
# 大量のデータを効率的に挿入
{:ok, _} = Exqlite.Sqlite3.execute(conn, "BEGIN TRANSACTION")

Enum.chunk_every(large_dataset, 1000)
|> Enum.each(fn chunk ->
  Enum.each(chunk, fn item ->
    MyApp.Queries.insert_item(conn, item)
  end)
end)

{:ok, _} = Exqlite.Sqlite3.execute(conn, "COMMIT")
```

## メモリデータベースの活用

### テスト環境での使用

```elixir
defmodule MyApp.TestHelper do
  def setup_test_db do
    {:ok, conn} = Exqlite.Sqlite3.open(":memory:")
    
    # スキーマを作成
    {:ok, _} = Exqlite.Sqlite3.execute(conn, """
      CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        email TEXT UNIQUE,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      );
    """)
    
    conn
  end
end
```

### 一時的なデータ処理

```elixir
# CSVデータの分析
def analyze_csv_data(csv_path) do
  {:ok, conn} = Exqlite.Sqlite3.open(":memory:")
  
  # 一時テーブルを作成
  {:ok, _} = Exqlite.Sqlite3.execute(conn, """
    CREATE TABLE temp_data (
      id INTEGER PRIMARY KEY,
      category TEXT,
      value REAL,
      date TEXT
    );
  """)
  
  # CSVデータをロード
  load_csv_to_sqlite(conn, csv_path)
  
  # 分析クエリを実行
  MyApp.Queries.analyze_data(conn)
end
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
    
  {:error, %Exqlite.Error{message: message}} ->
    # SQLiteエラー
    Logger.error("SQLite error: #{message}")
    {:error, :database_error}
end
```

## 制限事項と注意点

1. **同時書き込み**: SQLiteは同時に1つの書き込みトランザクションのみをサポート
2. **ネットワークファイルシステム**: NFSやSMB上のDBファイルは推奨されません
3. **大規模データベース**: 数GB以上のデータベースでは他のDBMSを検討してください
4. **型の柔軟性**: SQLiteは動的型付けのため、型の不整合に注意

## トラブルシューティング

### データベースがロックされる

```elixir
# ビジータイムアウトを増やす
{:ok, _} = Exqlite.Sqlite3.execute(conn, "PRAGMA busy_timeout = 10000")
```

### メモリ使用量が多い

```elixir
# キャッシュサイズを調整
{:ok, _} = Exqlite.Sqlite3.execute(conn, "PRAGMA cache_size = -2000")  # 2MB
```

### パフォーマンスが遅い

```elixir
# VACUUM実行でデータベースを最適化
{:ok, _} = Exqlite.Sqlite3.execute(conn, "VACUUM")

# 統計情報を更新
{:ok, _} = Exqlite.Sqlite3.execute(conn, "ANALYZE")
```