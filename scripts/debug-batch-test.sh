#!/bin/bash
# BatchTestのローカルデバッグスクリプト

# PostgreSQLコンテナを起動
echo "=== PostgreSQLコンテナを起動 ==="
docker run -d --name yesql-test-postgres \
  -e POSTGRES_PASSWORD=postgres \
  -e POSTGRES_DB=yesql_test \
  -p 5432:5432 \
  postgres:15

# 起動を待つ
echo "=== PostgreSQLの起動を待機 ==="
sleep 5

# 環境変数を設定
export CI=true
export DEBUG_BATCH_TEST=true
export POSTGRES_HOST=localhost

# 依存関係をインストール
echo "=== 依存関係をインストール ==="
mix deps.get
mix compile

# マイグレーションを実行
echo "=== マイグレーションを実行 ==="
mix ecto.create
mix ecto.migrate

# BatchTestを実行
echo "=== BatchTestを実行（デバッグモード） ==="
mix test test/batch_test.exs:135 --trace

# クリーンアップ
echo "=== クリーンアップ ==="
docker stop yesql-test-postgres
docker rm yesql-test-postgres
