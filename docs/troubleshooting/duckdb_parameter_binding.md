# DuckDB パラメータバインディング問題

## 概要

DuckDBは現在、プリペアドステートメントのパラメータバインディングを完全にはサポートしていません。
これにより、パラメータを使用するクエリで以下のようなエラーが発生します：

```
Invalid Input Error: Values were not provided for the following prepared statement parameters: 1
```

## 影響範囲

- パラメータを使用するすべてのDuckDBクエリ
- `:name`や`?`形式のパラメータプレースホルダー
- プリペアドステートメントを使用する処理

## 現在の対応

### 1. 直接SQL実行（パラメータなし）
```elixir
# 動作する
{:ok, result} = Duckdbex.query(conn, "SELECT * FROM users WHERE age > 25", [])
```

### 2. 文字列連結（非推奨）
```elixir
# 動作するが、SQLインジェクションのリスクあり
age = 25
sql = "SELECT * FROM users WHERE age > #{age}"
{:ok, result} = Duckdbex.query(conn, sql, [])
```

## 推奨される解決策

1. **YesQLドライバーでの対応**
   - DuckDBドライバーでパラメータを直接SQLに埋め込む処理を実装
   - 適切なエスケープ処理を含める

2. **DuckDBの更新待ち**
   - DuckDBがパラメータバインディングを完全サポートするまで待つ
   - 関連Issue: https://github.com/duckdb/duckdb/issues/...

## テストの対応

現在、DuckDBのパラメータテストは以下の理由で一部スキップされています：

1. パラメータバインディングのサポート不足
2. プリペアドステートメントの制限

## 今後の計画

1. DuckDBドライバーでの安全なパラメータ埋め込み実装
2. DuckDBの公式サポートを待つ
3. 代替データベースの検討（分析用途）