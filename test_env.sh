#\!/bin/bash
# データベース接続設定
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

# テスト実行時の環境変数
export MIX_ENV=test
export FULL_TEST=true
