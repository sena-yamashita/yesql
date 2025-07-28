# CI調査レポート v2 - 2025-07-28

## 問題の詳細分析

### 根本原因
1. **test_helper.exsで無条件にPostgreSQL Repoを起動**
   - すべてのテスト環境でPostgreSQLへの接続を試みる
   - SQLiteテストやDuckDBテストでも不要なPostgreSQL接続を要求

2. **config/test.exsの設定**
   ```elixir
   config :yesql,
     ecto_repos: [Yesql.TestRepo.Postgres, Yesql.TestRepo.MySQL, Yesql.TestRepo.MSSQL]
   ```
   - すべてのRepoが登録されているため、アプリケーション起動時に全接続を試みる可能性

### 現在の動作
- SQLiteテスト（SQLITE_TEST=true）→ PostgreSQL接続エラー
- DuckDBテスト（DUCKDB_TEST=true）→ PostgreSQL接続エラー
- 通常のテスト → PostgreSQL接続が必要

## 解決方針

### 環境変数による条件分岐
1. **PostgreSQLが必要な場合**
   - デフォルト（環境変数なし）
   - POSTGRESQL_TEST=true
   - CI=true（DuckDB/SQLiteテスト以外）

2. **MySQLが必要な場合**
   - MYSQL_TEST=true

3. **MSSQLが必要な場合**
   - MSSQL_TEST=true

4. **接続不要な場合**
   - SQLITE_TEST=true（SQLiteは直接接続）
   - DUCKDB_TEST=true（DuckDBは直接接続）

### 実装方針
test_helper.exsで環境変数をチェックし、必要なRepoのみを起動：

```elixir
# PostgreSQLが必要な場合のみ起動
if should_start_postgres_repo?() do
  start_postgres_repo_with_migrations()
end

# MySQLが必要な場合のみ起動
if System.get_env("MYSQL_TEST") == "true" do
  start_mysql_repo_with_migrations()
end

# MSSQLが必要な場合のみ起動
if System.get_env("MSSQL_TEST") == "true" do
  start_mssql_repo_with_migrations()
end
```

## メリット
1. 各ドライバーテストが独立して動作
2. 不要な接続を作成しない
3. エラーメッセージが明確になる
4. テスト実行時間の短縮

## デグレード防止
1. 既存のテストは変更なし
2. 環境変数による制御のみ追加
3. デフォルト動作は維持（PostgreSQL接続）