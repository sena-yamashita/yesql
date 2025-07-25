# Oracle設定

このガイドでは、YesqlでOracleドライバーを使用する方法を説明します。

## インストール

`mix.exs`に以下の依存関係を追加してください：

```elixir
defp deps do
  [
    {:yesql, "~> 2.0"},
    {:jamdb_oracle, "~> 0.5"}
  ]
end
```

## 基本的な使用方法

```elixir
defmodule MyApp.Queries do
  use Yesql, driver: :oracle
  
  Yesql.defquery("queries/users.sql")
end
```

## 接続の設定

### 基本的な接続

```elixir
{:ok, conn} = Jamdb.Oracle.start_link(
  hostname: "localhost",
  port: 1521,
  database: "XE",  # SIDまたはサービス名
  username: "myapp",
  password: "password",
  parameters: [
    nls_date_format: "YYYY-MM-DD HH24:MI:SS"
  ]
)
```

### TNS名を使用した接続

```elixir
{:ok, conn} = Jamdb.Oracle.start_link(
  tns: "mydb_tns",
  username: "myapp",
  password: "password"
)
```

### Oracle Cloudへの接続

```elixir
{:ok, conn} = Jamdb.Oracle.start_link(
  hostname: "your-db.adb.region.oraclecloudapps.com",
  port: 1522,
  database: "your_service_name",
  username: "your_username",
  password: "your_password",
  ssl: true,
  ssl_opts: [
    verify: :verify_peer,
    cacertfile: "/path/to/wallet/ca-cert.pem"
  ]
)
```

## SQLファイルの作成

Oracleは位置パラメータ（`:1`, `:2`...）を使用しますが、Yesqlでは通常の名前付きパラメータを使用できます：

```sql
-- queries/get_user.sql
-- name: get_user
SELECT * FROM users WHERE id = :id;

-- queries/search_users.sql
-- name: search_users
SELECT * FROM (
  SELECT * FROM users 
  WHERE name LIKE :name_pattern
    AND age >= :min_age
  ORDER BY created_at DESC
)
WHERE ROWNUM <= :limit;
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

YesqlのOracleドライバーは、名前付きパラメータを自動的にOracleの位置パラメータに変換します：

- 入力: `:name`, `:age`
- 出力: `:1`, `:2`...

パラメータは、SQLクエリ内での**出現順序**に基づいて番号付けされます。

## 結果の形式

Oracleドライバーは結果をマップのリストとして返します。カラム名は小文字に変換されます：

```elixir
{:ok, [
  %{id: 1, name: "Alice", age: 25},
  %{id: 2, name: "Bob", age: 30}
]}
```

## トランザクション

jamdb_oracleは自動コミットモードで動作します。明示的なトランザクション制御が必要な場合：

```elixir
# トランザクション開始
Jamdb.Oracle.query!(conn, "BEGIN")

try do
  # 複数のクエリを実行
  {:ok, _} = MyApp.Queries.insert_user(conn, name: "Alice", age: 25)
  {:ok, _} = MyApp.Queries.update_balance(conn, user_id: 1, amount: 100)
  
  # コミット
  Jamdb.Oracle.query!(conn, "COMMIT")
rescue
  error ->
    # ロールバック
    Jamdb.Oracle.query!(conn, "ROLLBACK")
    reraise error, __STACKTRACE__
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
    
  {:error, %{code: code, message: message}} ->
    # Oracleエラー
    Logger.error("Oracle error #{code}: #{message}")
    {:error, :database_error}
end
```

## Oracle固有の機能

### シーケンスの使用

```sql
-- queries/insert_user_with_sequence.sql
-- name: insert_user_with_sequence
INSERT INTO users (id, name, age)
VALUES (users_seq.NEXTVAL, :name, :age)
RETURNING id INTO :id;
```

### PL/SQLブロックの実行

```elixir
# PL/SQLブロックの実行
{:ok, result} = Jamdb.Oracle.query(conn, """
  DECLARE
    v_count NUMBER;
  BEGIN
    SELECT COUNT(*) INTO v_count FROM users WHERE age > :1;
    :2 := v_count;
  END;
""", [25, {:out, :integer}])
```

### ストアドプロシージャの呼び出し

```elixir
# ストアドプロシージャの呼び出し
{:ok, result} = Jamdb.Oracle.query(conn, 
  "BEGIN get_user_by_id(:1, :2, :3); END;", 
  [user_id, {:out, :string}, {:out, :integer}]
)
```

## データ型の対応

| Oracle型 | Elixir型 |
|---------|----------|
| NUMBER | integer/float |
| VARCHAR2 | String.t |
| DATE | DateTime.t |
| TIMESTAMP | DateTime.t |
| CLOB | String.t |
| BLOB | binary |

## パフォーマンスのヒント

1. **接続プール**: 本番環境では接続プールを使用してください
2. **バインド変数**: Yesqlは自動的にバインド変数を使用するため、SQLインジェクション対策とパフォーマンスが向上します
3. **フェッチサイズ**: 大量のデータを取得する場合は、フェッチサイズを調整してください

```elixir
{:ok, conn} = Jamdb.Oracle.start_link(
  # 他のオプション...
  parameters: [
    prefetch_rows: 1000
  ]
)
```

## 注意事項

- Oracleの識別子（テーブル名、カラム名）は大文字小文字を区別しません
- 30文字を超える識別子はOracle 12.2以降でサポートされます
- `NULL`値は`nil`として返されます
- 日付型はUTCとして扱われます

## トラブルシューティング

### ORA-12154: TNS:指定された接続識別子を解決できませんでした

TNS名が正しく設定されているか、またはホスト名、ポート、データベース名が正しいことを確認してください。

### ORA-01017: ユーザー名/パスワードが無効です

ユーザー名とパスワードが正しいことを確認してください。Oracleではユーザー名は通常大文字です。

### 文字化け

NLS設定を確認してください：

```elixir
{:ok, conn} = Jamdb.Oracle.start_link(
  # 他のオプション...
  parameters: [
    nls_lang: "JAPANESE_JAPAN.AL32UTF8"
  ]
)