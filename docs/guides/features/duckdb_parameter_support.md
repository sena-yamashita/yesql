# DuckDB パラメータクエリのサポート

## 概要

YesQLのDuckDBドライバーは、DuckDBexライブラリを通じてパラメータクエリをサポートしています。v2.1.3以降、**適応的パラメータ処理**により、DuckDBの制限を自動的かつ透過的に回避します。さらに、**複数ステートメントの実行**もサポートしています。

## 適応的パラメータ処理（v2.1.3以降）

### 仕組み

DuckDBドライバーは以下の適応的アプローチを採用しています：

1. **自動試行**: まずネイティブパラメータバインディングを試行
2. **エラー検出**: パラメータ関連のエラーを自動的に検出
3. **自動フォールバック**: エラーが発生した場合、文字列置換に切り替え
4. **キャッシュ最適化**: クエリパターンをキャッシュし、2回目以降は最適な方法を即座に選択

### メリット

- **メンテナンスフリー**: 新しいDuckDB関数が追加されても自動的に対応
- **最高のパフォーマンス**: 可能な限りネイティブパラメータバインディングを使用
- **完全な透過性**: 開発者は実装の詳細を意識する必要がない
- **将来の互換性**: DuckDBがパラメータサポートを改善した場合も自動的に対応

## パラメータサポートの詳細

### 通常のクエリ
DuckDBexは`$1`, `$2`形式のプレースホルダーを使用したパラメータクエリを完全にサポートしています：

```elixir
# ネイティブパラメータバインディングが使用される
Yesql.Driver.execute(driver, conn, "SELECT * FROM users WHERE id = $1", [123])
```

### ファイル関数での自動処理
以下のようなファイル関数を含むクエリは、自動的に文字列置換で処理されます：

```elixir
# 自動的に文字列置換にフォールバック
Yesql.Driver.execute(driver, conn, 
  "CREATE TABLE data AS SELECT * FROM read_csv_auto($1)", 
  ["/path/to/file.csv"])

# COPY TOコマンドも自動処理
Yesql.Driver.execute(driver, conn,
  "COPY table_name TO $1 (HEADER, DELIMITER ',')",
  ["/path/to/export.csv"])
```

### パフォーマンス

キャッシュにより、同じクエリパターンの2回目以降の実行は約20%高速化されます：

```elixir
# 初回実行: パラメータ処理方法を自動検出
{:ok, result1} = Yesql.Driver.execute(driver, conn, sql, params)  # 750μs

# 2回目以降: キャッシュから最適な方法を選択
{:ok, result2} = Yesql.Driver.execute(driver, conn, sql, params)  # 600μs
```

## 複数ステートメントのサポート

### 概要

DuckDBexの`query/3`（パラメータ付き）は複数ステートメントをサポートしていませんが、YesQLのDuckDBドライバーは自動的にこの制限を回避します：

1. 文字列置換モードで実行される場合、複数ステートメントを自動検出
2. セミコロンで分割して個別に実行
3. エラーが発生した場合は即座に停止
4. 最後のステートメントの結果を返す

### 使用例

```elixir
# SQLファイル: queries/create_and_insert.sql
CREATE TABLE IF NOT EXISTS :table_name AS 
SELECT * FROM read_csv_auto(:file_path) WHERE 1=0;

INSERT INTO :table_name 
SELECT * FROM read_csv_auto(:file_path);
```

```elixir
# Elixirコード
defmodule MyApp.Queries do
  use Yesql, driver: :duckdb
  
  Yesql.defquery("queries/create_and_insert.sql")
end

# 使用時 - 複数ステートメントが自動的に実行される
MyApp.Queries.create_and_insert(conn, 
  table_name: "sales_data",
  file_path: "/path/to/sales.csv"
)
```

### トランザクション処理

```sql
-- queries/transaction_import.sql
BEGIN TRANSACTION;
CREATE TABLE :table_name (id INTEGER, name VARCHAR, value DOUBLE);
INSERT INTO :table_name VALUES (1, 'Test', 100.0);
COMMIT;
```

### 注意事項

- エラーが発生した場合、そこで実行が停止します
- トランザクションは明示的に管理する必要があります
- 各ステートメントは独立して実行されるため、一部のみ成功する可能性があります

## 使用例

### 基本的な使用方法
```elixir
defmodule MyApp.Queries do
  use Yesql, driver: :duckdb
  
  # SQLファイル: queries/user_by_id.sql
  # SELECT * FROM users WHERE id = $1
  Yesql.defquery("queries/user_by_id.sql")
  
  # SQLファイル: queries/import_csv.sql
  # CREATE TABLE data AS SELECT * FROM read_csv_auto($1)
  Yesql.defquery("queries/import_csv.sql")
end

# 使用
{:ok, db} = Duckdbex.open("myapp.db")
{:ok, conn} = Duckdbex.connection(db)

# 通常のクエリ（ネイティブパラメータ使用）
{:ok, users} = MyApp.Queries.user_by_id(conn, id: 123)

# ファイル関数（自動的に文字列置換）
{:ok, _} = MyApp.Queries.import_csv(conn, ["/path/to/data.csv"])
```

### 様々なファイル関数の例

```elixir
# CSVファイルの読み込み
sql = "CREATE TABLE sales AS SELECT * FROM read_csv_auto($1)"
Yesql.Driver.execute(driver, conn, sql, ["sales.csv"])

# Parquetファイルの読み込み
sql = "INSERT INTO analytics SELECT * FROM read_parquet($1)"
Yesql.Driver.execute(driver, conn, sql, ["data.parquet"])

# Excelファイルの読み込み
sql = "CREATE TABLE report AS SELECT * FROM read_xlsx($1)"
Yesql.Driver.execute(driver, conn, sql, ["report.xlsx"])

# CSVへのエクスポート
sql = "COPY customers TO $1 (FORMAT CSV, HEADER)"
Yesql.Driver.execute(driver, conn, sql, ["customers.csv"])
```

## セキュリティ上の考慮事項

適応的アプローチは自動的に安全な文字列エスケープを行いますが、以下の点に注意してください：

1. **入力の検証**: ファイルパスは常に検証してください
2. **ディレクトリトラバーサル**: `../`を含むパスに注意
3. **SQLインジェクション**: 動的SQLの生成は避けてください

```elixir
# 良い例：パスの検証
def import_csv(conn, filename) do
  # ファイル名のみを許可（パスを含まない）
  if String.contains?(filename, "/") or String.contains?(filename, "\\") do
    {:error, "Invalid filename"}
  else
    path = Path.join("/safe/directory", filename)
    Yesql.Driver.execute(driver, conn, 
      "CREATE TABLE data AS SELECT * FROM read_csv_auto($1)", 
      [path])
  end
end
```

## トラブルシューティング

### デバッグ方法

ETSキャッシュの状態を確認：

```elixir
# キャッシュの内容を表示
:ets.tab2list(:yesql_duckdb_query_cache)
```

### キャッシュのクリア

必要に応じてキャッシュをクリア：

```elixir
# キャッシュテーブルを削除
:ets.delete(:yesql_duckdb_query_cache)
```

## 技術的な詳細

### エラーパターンの検出

以下のエラーメッセージを検出して自動的にフォールバック：

- "Values were not provided"
- "prepared statement parameter"
- "Cannot use positional parameters"
- "Binder Error"
- "Invalid Input Error"
- "Parser Error: syntax error at or near \"$"

### キャッシュキーの生成

クエリパターンからキャッシュキーを生成：

```elixir
# パラメータを正規化してハッシュ化
sql
|> String.replace(~r/\$\d+/, "?")
|> String.downcase()
|> String.trim()
|> :erlang.phash2()
```

## 関連ファイル

- `/lib/yesql/driver/duckdb.ex` - DuckDBドライバー実装（適応的アプローチ）
- `/test/duckdb_parameter_test.exs` - パラメータテスト
- `/test_adaptive_duckdb.exs` - 適応的アプローチのテスト