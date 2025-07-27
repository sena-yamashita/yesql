# YesQL Docker テスト環境

このディレクトリには、YesQLのテストをローカルで実行するためのDocker環境が含まれています。

## 概要

GitHub CIと同じ環境をローカルで再現し、すべてのデータベースドライバーのテストを実行できます。

## 対応データベース

- PostgreSQL 15
- MySQL 8.0
- Microsoft SQL Server 2022
- SQLite（ファイルベース）
- DuckDB（ファイルベース）

## 使い方

### 1. すべてのテストを実行

```bash
./docker/run-tests.sh all
```

### 2. 特定のデータベースのテストのみ実行

```bash
# PostgreSQLのテスト
./docker/run-tests.sh postgres

# MySQLのテスト
./docker/run-tests.sh mysql

# SQL Serverのテスト
./docker/run-tests.sh mssql

# SQLiteのテスト
./docker/run-tests.sh sqlite

# DuckDBのテスト
./docker/run-tests.sh duckdb
```

### 3. Docker Composeを直接使用

```bash
# サービスの起動
docker-compose -f docker/docker-compose.yml up -d

# サービスの停止
docker-compose -f docker/docker-compose.yml down

# ログの確認
docker-compose -f docker/docker-compose.yml logs -f

# 特定のサービスのログ
docker-compose -f docker/docker-compose.yml logs -f postgres
```

### 4. 環境変数を使用したテスト

```bash
# 環境変数ファイルを読み込んで実行
source docker/.env.test
mix test
```

## トラブルシューティング

### ポートの競合

既存のサービスとポートが競合する場合は、`docker-compose.yml`のポート設定を変更してください。

```yaml
ports:
  - "15432:5432"  # PostgreSQL
  - "13306:3306"  # MySQL
  - "11433:1433"  # MSSQL
```

### メモリ不足

すべてのサービスを同時に実行するとメモリが不足する場合があります。
必要なサービスのみを起動してください：

```bash
# PostgreSQLのみ起動
docker-compose -f docker/docker-compose.yml up -d postgres

# MySQLとPostgreSQLのみ起動
docker-compose -f docker/docker-compose.yml up -d postgres mysql
```

### データの永続化

データベースのデータは名前付きボリュームに保存されます。
データをクリアしたい場合：

```bash
# ボリュームも含めて削除
docker-compose -f docker/docker-compose.yml down -v
```

## CI環境との違い

- ローカル環境では、データベースのデータが永続化されます
- ヘルスチェックの設定が若干異なる場合があります
- メモリ制限やCPU制限は設定されていません

## 開発のヒント

1. **テストの高速化**: 特定のデータベースのテストのみを実行
2. **デバッグ**: `docker logs`でデータベースのログを確認
3. **接続テスト**: 各データベースに直接接続して確認

```bash
# PostgreSQL
psql -h localhost -U postgres -d yesql_test

# MySQL
mysql -h 127.0.0.1 -u root -proot yesql_test

# MSSQL
sqlcmd -S localhost -U sa -P 'YourStrong@Passw0rd'
```