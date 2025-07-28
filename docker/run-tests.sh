#!/bin/bash

# Docker環境でYesQLのテストを実行するスクリプト

set -e

# 色付き出力
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== YesQL Docker Test Runner ===${NC}"

# 引数のパース
TEST_TYPE="${1:-all}"

# Docker Composeでサービスを起動
echo -e "\n${YELLOW}Starting database services...${NC}"
docker-compose -f docker/docker-compose.yml up -d

# サービスの起動を待つ
echo -e "\n${YELLOW}Waiting for services to be ready...${NC}"
sleep 10

# データベースの準備状態を確認
echo -e "\n${YELLOW}Checking database connections...${NC}"

# PostgreSQL
until docker exec yesql_postgres pg_isready; do
  echo "Waiting for PostgreSQL..."
  sleep 2
done
echo -e "${GREEN}PostgreSQL is ready!${NC}"

# MySQL
until docker exec yesql_mysql mysqladmin ping -h localhost --silent; do
  echo "Waiting for MySQL..."
  sleep 2
done
echo -e "${GREEN}MySQL is ready!${NC}"

# MSSQL - tools18を使用し、-Cオプションで証明書検証をスキップ
until docker exec yesql_mssql /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'YourStrong@Passw0rd' -Q 'SELECT 1' -C > /dev/null 2>&1; do
  echo "Waiting for MSSQL..."
  sleep 2
done
echo -e "${GREEN}MSSQL is ready!${NC}"

# 環境変数の設定
export POSTGRES_HOST=localhost
export POSTGRES_PORT=5432
export POSTGRES_USER=postgres
export POSTGRES_PASSWORD=postgres
export POSTGRES_DATABASE=yesql_test

export MYSQL_HOST=localhost
export MYSQL_PORT=3306
export MYSQL_USER=root
export MYSQL_PASSWORD=root
export MYSQL_DATABASE=yesql_test

export MSSQL_HOST=localhost
export MSSQL_PORT=1433
export MSSQL_USER=sa
export MSSQL_PASSWORD='YourStrong@Passw0rd'
export MSSQL_DATABASE=master

# 依存関係の取得
echo -e "\n${YELLOW}Installing dependencies...${NC}"
mix deps.get

# コンパイルしてテストサポートモジュールを利用可能にする
echo -e "\n${YELLOW}Compiling project...${NC}"
MIX_ENV=test mix compile

# データベースセットアップ
echo -e "\n${YELLOW}Setting up databases...${NC}"

# PostgreSQL
docker exec yesql_postgres psql -U postgres -c "CREATE DATABASE yesql_test" 2>/dev/null || echo "PostgreSQL database already exists: yesql_test"

# MySQL  
docker exec yesql_mysql mysql -uroot -proot -e "CREATE DATABASE IF NOT EXISTS yesql_test" || echo "Failed to create MySQL database"

# MSSQL
docker exec yesql_mssql /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'YourStrong@Passw0rd' -C -Q "IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = 'yesql_test') CREATE DATABASE yesql_test" || echo "Failed to create MSSQL database"

# テストの実行
case "$TEST_TYPE" in
  "all")
    echo -e "\n${GREEN}Running all tests...${NC}"
    
    # PostgreSQL and core tests
    echo -e "\n${YELLOW}Running PostgreSQL and core tests...${NC}"
    CI=true FULL_TEST=true POSTGRESQL_STREAM_TEST=true mix test --exclude mysql --exclude duckdb --exclude mssql --exclude oracle --exclude sqlite
    
    # MySQL tests
    echo -e "\n${YELLOW}Running MySQL tests...${NC}"
    CI=true MYSQL_TEST=true MYSQL_STREAM_TEST=true mix test --only mysql
    
    # SQLite tests
    echo -e "\n${YELLOW}Running SQLite tests...${NC}"
    CI=true SQLITE_TEST=true SQLITE_STREAM_TEST=true mix test --only sqlite
    
    # MSSQL tests
    echo -e "\n${YELLOW}Running MSSQL tests...${NC}"
    CI=true MSSQL_TEST=true MSSQL_STREAM_TEST=true mix test --only mssql
    
    # DuckDB tests
    echo -e "\n${YELLOW}Running DuckDB tests...${NC}"
    CI=true DUCKDB_TEST=true DUCKDB_STREAM_TEST=true mix test --only duckdb
    ;;
    
  "postgres")
    echo -e "\n${GREEN}Running PostgreSQL tests only...${NC}"
    CI=true FULL_TEST=true POSTGRESQL_STREAM_TEST=true mix test --exclude mysql --exclude duckdb --exclude mssql --exclude oracle --exclude sqlite
    ;;
    
  "mysql")
    echo -e "\n${GREEN}Running MySQL tests only...${NC}"
    CI=true MYSQL_TEST=true MYSQL_STREAM_TEST=true mix test --only mysql
    ;;
    
  "sqlite")
    echo -e "\n${GREEN}Running SQLite tests only...${NC}"
    CI=true SQLITE_TEST=true SQLITE_STREAM_TEST=true mix test --only sqlite
    ;;
    
  "mssql")
    echo -e "\n${GREEN}Running MSSQL tests only...${NC}"
    CI=true MSSQL_TEST=true MSSQL_STREAM_TEST=true mix test --only mssql
    ;;
    
  "duckdb")
    echo -e "\n${GREEN}Running DuckDB tests only...${NC}"
    CI=true DUCKDB_TEST=true DUCKDB_STREAM_TEST=true mix test --only duckdb
    ;;
    
  *)
    echo -e "${RED}Unknown test type: $TEST_TYPE${NC}"
    echo "Usage: $0 [all|postgres|mysql|sqlite|mssql|duckdb]"
    exit 1
    ;;
esac

echo -e "\n${GREEN}Tests completed!${NC}"

# CI環境では自動的にスキップ
if [ -z "$CI" ]; then
  # オプション: テスト後にサービスを停止
  read -p "Stop database services? (y/N) " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    docker-compose -f docker/docker-compose.yml down
  fi
fi