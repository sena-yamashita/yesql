# DuckDB パラメータクエリのサポート

## 概要

YesQLのDuckDBドライバーは、DuckDBexライブラリを通じてパラメータクエリをサポートしています。通常のSQLクエリではネイティブなパラメータバインディングが使用されますが、ファイル関数を含むクエリでは特別な処理が必要です。

## パラメータサポート

### 通常のクエリ
DuckDBexは`$1`, `$2`形式のプレースホルダーを使用したパラメータクエリを完全にサポートしています：

```elixir
# 通常のパラメータクエリは正常に動作
Duckdbex.query(conn, "SELECT * FROM users WHERE id = $1", [123])
```

### ファイル関数の制限
以下のファイル関数内ではパラメータバインディングが動作しないため、YesQLが自動的に文字列置換を行います：

- `read_csv_auto()`
- `read_csv()`
- `read_json_auto()`
- `read_json()`
- `read_parquet()`
- `read_excel()`
- `write_csv()`
- `write_parquet()`
- `write_json()`

これらの関数を含むクエリでは、YesQLドライバーが自動的にパラメータを安全に置換します：

1. **自動検出**：SQLにファイル関数が含まれているかを検出
2. **安全な置換**：文字列値を適切にエスケープして置換
3. **透過的な処理**：ユーザーは通常通りパラメータを使用可能

## 使用例

### 基本的な使用方法
```elixir
defmodule MyApp.Queries do
  use Yesql, driver: :duckdb
  
  # SQLファイル: queries/user_by_id.sql
  # SELECT * FROM users WHERE id = $1
  Yesql.defquery("queries/user_by_id.sql")
end

# 使用
{:ok, db} = Duckdbex.open("myapp.db")
{:ok, conn} = Duckdbex.connection(db)

# パラメータは内部で文字列置換される
{:ok, users} = MyApp.Queries.user_by_id(conn, id: 123)
```

### ファイルパスの処理
```elixir
# SQLファイル: queries/import_csv.sql
# CREATE OR REPLACE TABLE data AS SELECT * FROM read_csv_auto($1)
Yesql.defquery("queries/import_csv.sql")

# 使用
csv_path = "/path/to/data.csv"
{:ok, _} = MyApp.Queries.import_csv(conn, [csv_path])
```

## セキュリティ上の注意

現在の実装は文字列置換を使用しているため、以下の点に注意してください：

1. **信頼できない入力**：ユーザー入力を直接渡さず、必ず検証してください
2. **文字列のエスケープ**：ドライバーは基本的なエスケープを行いますが、完全ではない可能性があります
3. **動的SQL**：可能な限り静的なSQLを使用し、動的に生成されるSQLは避けてください

## 今後の改善

1. **DuckDBexの更新監視**：パラメータサポートが追加される可能性
2. **代替ライブラリの検討**：他のDuckDB Elixirバインディングの評価
3. **より安全な実装**：プリペアドステートメントのエミュレーション

## 代替案

パラメータクエリが必須の場合は、以下を検討してください：

1. **他のデータベース**：PostgreSQLやMySQLを使用
2. **直接SQL実行**：YesQLを使わずDuckDBexを直接使用
3. **バッチ処理**：パラメータなしのクエリで処理

## 関連ファイル

- `/lib/yesql/driver/duckdb.ex` - DuckDBドライバー実装
- `/test/duckdb_parameter_test.exs` - パラメータテスト
- `/guides/duckdb_configuration.md` - DuckDB設定ガイド