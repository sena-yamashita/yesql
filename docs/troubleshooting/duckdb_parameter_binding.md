# DuckDB パラメータバインディング問題

## 概要

DuckDBはプリペアドステートメントをサポートしていますが、Duckdbexライブラリの`query`関数は
直接的なパラメータバインディングをサポートしていません。そのため、以下のようなエラーが発生します：

```
Invalid Input Error: Values were not provided for the following prepared statement parameters: 1
```

## 技術的詳細

DuckDBとDuckdbexでは、プリペアドステートメントを使用する場合、以下の手順が必要です：

1. `prepare_statement(conn, sql)` でステートメントを準備
2. `execute_statement(conn, statement, params)` でパラメータをバインドして実行

しかし、`Duckdbex.query(conn, sql, params)` は第3引数のパラメータを無視するため、
パラメータが提供されないというエラーが発生します。

## 影響範囲

- パラメータを使用するすべてのDuckDBクエリ
- `:name`形式のパラメータプレースホルダー（YesQLで$1形式に変換される）
- 直接的な`query`関数呼び出し

## 現在の対応

YesQLのDuckDBドライバー（`Yesql.Driver.DuckDB`）では、適応的なアプローチを実装しています：

1. **初回実行時**：
   - まず`Duckdbex.query(conn, sql, params)`でパラメータ付きクエリを試行
   - エラーが発生した場合、安全な文字列置換にフォールバック
   - 実行方法をキャッシュに保存

2. **2回目以降**：
   - キャッシュから最適な実行方法を選択
   - パフォーマンスの最適化

### 安全な文字列置換

文字列置換を行う場合も、以下の安全対策を実装：

```elixir
# 文字列の場合：シングルクォートをエスケープ
"O'Brien" → "'O''Brien'"

# 数値の場合：そのまま文字列化
123 → "123"

# NULL値の場合：
nil → "NULL"

# 日付型の場合：ISO形式に変換
~D[2024-01-01] → "'2024-01-01'"
```

## 推奨される解決策

### 1. Duckdbexライブラリの改善

`prepare_statement`と`execute_statement`を使用するように修正：

```elixir
# 現在の実装（動作しない）
Duckdbex.query(conn, "SELECT * FROM users WHERE age > $1", [25])

# 改善案
{:ok, stmt} = Duckdbex.prepare_statement(conn, "SELECT * FROM users WHERE age > $1")
{:ok, result} = Duckdbex.execute_statement(conn, stmt, [25])
```

### 2. YesQLドライバーの更新

現在のドライバーは既に適応的なアプローチを実装していますが、
`prepare_statement`/`execute_statement`を使用するように改善することで、
より効率的なパラメータバインディングが可能になります。

## テストの対応

DuckDBのパラメータテストで一部エラーが発生していますが、
これは`Duckdbex.query`の第3引数がパラメータとして機能しないためです。
ドライバーは自動的に文字列置換にフォールバックして動作します。

## 今後の計画

1. Duckdbexライブラリへのプルリクエスト（`query`関数の改善）
2. YesQLドライバーで`prepare_statement`/`execute_statement`のサポート追加
3. パフォーマンステストの実施