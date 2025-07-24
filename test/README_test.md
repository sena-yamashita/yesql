# テスト実行ガイド

## 基本的なテスト実行

```bash
# PostgreSQLデータベースを作成
createdb yesql_test

# 全てのテストを実行（DuckDB以外）
mix test
```

## DuckDBテストの実行

DuckDBテストはデフォルトでスキップされます。実行するには環境変数を設定します：

```bash
# DuckDBテストを含む全てのテストを実行
DUCKDB_TEST=true mix test

# DuckDBテストのみ実行
DUCKDB_TEST=true mix test --only duckdb

# 特定のDuckDBテストファイルを実行
DUCKDB_TEST=true mix test test/duckdb_test.exs
```

## タグによるテスト実行

```bash
# DuckDB以外のテストを実行
mix test --exclude duckdb

# CI環境でのテスト（DuckDBテストをスキップ）
mix test --exclude skip_on_ci
```

## トラブルシューティング

### PostgreSQLテストが失敗する場合
- データベース `yesql_test` が存在することを確認
- PostgreSQLが起動していることを確認
- 接続設定（ユーザー名、パスワード）が正しいことを確認

### DuckDBテストが実行されない場合
- `DUCKDB_TEST=true` 環境変数が設定されていることを確認
- DuckDBex依存関係がインストールされていることを確認：`mix deps.get`