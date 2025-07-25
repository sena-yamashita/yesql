#!/bin/bash
# YesQL ベンチマーク実行スクリプト

echo "YesQL パフォーマンスベンチマーク"
echo "=================================="
echo ""

# デフォルト値の設定
PGHOST=${PGHOST:-localhost}
PGUSER=${PGUSER:-postgres}
PGPASSWORD=${PGPASSWORD:-postgres}
PGDATABASE=${PGDATABASE:-yesql_bench}

MYSQL_HOST=${MYSQL_HOST:-localhost}
MYSQL_USER=${MYSQL_USER:-root}
MYSQL_PASSWORD=${MYSQL_PASSWORD:-password}
MYSQL_DATABASE=${MYSQL_DATABASE:-yesql_bench}

# ベンチマークの種類を選択
if [ "$1" == "all" ] || [ -z "$1" ]; then
    POSTGRESQL_BENCH=true
    MYSQL_BENCH=true
    OVERHEAD_BENCH=true
elif [ "$1" == "postgresql" ]; then
    POSTGRESQL_BENCH=true
elif [ "$1" == "mysql" ]; then
    MYSQL_BENCH=true
elif [ "$1" == "overhead" ]; then
    OVERHEAD_BENCH=true
else
    echo "使用方法: $0 [all|postgresql|mysql|overhead]"
    echo ""
    echo "  all        - 全てのベンチマークを実行（デフォルト）"
    echo "  postgresql - PostgreSQLベンチマークのみ"
    echo "  mysql      - MySQLベンチマークのみ"
    echo "  overhead   - 抽象化レイヤーのオーバーヘッド測定のみ"
    exit 1
fi

# 環境変数の設定と実行
export POSTGRESQL_BENCH
export MYSQL_BENCH
export OVERHEAD_BENCH
export PGHOST
export PGUSER
export PGPASSWORD
export PGDATABASE
export MYSQL_HOST
export MYSQL_USER
export MYSQL_PASSWORD
export MYSQL_DATABASE

# 依存関係の取得
echo "依存関係を取得中..."
mix deps.get

# ベンチマークの実行
echo ""
echo "ベンチマークを実行中..."
echo ""

MIX_ENV=bench mix run bench/driver_benchmark.exs