#!/bin/bash
# ローカルCI環境セットアップスクリプト

set -e

echo "=== YesQL ローカルCI環境セットアップ ==="

# actのインストール確認
if ! command -v act &> /dev/null; then
    echo "actがインストールされていません。インストールしてください："
    echo "  macOS: brew install act"
    echo "  Linux: curl -s https://raw.githubusercontent.com/nektos/act/master/install.sh | sudo bash"
    exit 1
fi

# Dockerの確認
if ! command -v docker &> /dev/null; then
    echo "Dockerがインストールされていません。Docker Desktopをインストールしてください。"
    exit 1
fi

# .actディレクトリの作成
echo "=== .actディレクトリを作成 ==="
mkdir -p .act

# 環境変数ファイルの作成
echo "=== CI環境変数ファイルを作成 ==="
cat > .act/env << 'EOF'
CI=true
MIX_ENV=test
POSTGRES_HOST=postgres
POSTGRES_USER=postgres
POSTGRES_PASSWORD=postgres
POSTGRES_DATABASE=yesql_test
POSTGRES_PORT=5432
DEBUG_BATCH_TEST=true
EOF

echo "=== BatchTestデバッグ用のテストスクリプトを作成 ==="
cat > scripts/debug-batch-test.sh << 'EOF'
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
EOF

chmod +x scripts/debug-batch-test.sh

echo "=== 簡易実行スクリプトを作成 ==="
cat > scripts/run-local-ci.sh << 'EOF'
#!/bin/bash
# actを使ったローカルCI実行スクリプト

# 軽量Dockerイメージを使用
ACT_PLATFORM="ubuntu-latest=catthehacker/ubuntu:act-latest"

echo "使用方法:"
echo "  ./scripts/run-local-ci.sh            # 全ワークフローを一覧表示"
echo "  ./scripts/run-local-ci.sh elixir     # Elixir CIを実行"
echo "  ./scripts/run-local-ci.sh ci         # Database Testsを実行"
echo "  ./scripts/run-local-ci.sh batch      # BatchTestデバッグを実行"

case "$1" in
  "elixir")
    echo "=== Elixir CIを実行 ==="
    act -W .github/workflows/elixir.yml -P $ACT_PLATFORM --env-file .act/env
    ;;
  "ci")
    echo "=== Database Testsを実行 ==="
    act -W .github/workflows/ci.yml -P $ACT_PLATFORM --env-file .act/env
    ;;
  "batch")
    echo "=== BatchTestデバッグを実行 ==="
    act -W .github/workflows/batch-test-debug.yml -P $ACT_PLATFORM --env-file .act/env
    ;;
  *)
    echo "=== 利用可能なワークフロー ==="
    act -l
    ;;
esac
EOF

chmod +x scripts/run-local-ci.sh

echo ""
echo "=== セットアップ完了 ==="
echo ""
echo "次のコマンドでローカルCI環境を使用できます："
echo "  ./scripts/debug-batch-test.sh     # BatchTestをローカルでデバッグ"
echo "  ./scripts/run-local-ci.sh         # actでCI環境を再現"
echo ""
echo "BatchTest問題の調査手順："
echo "1. ./scripts/debug-batch-test.sh を実行してローカルで問題を再現"
echo "2. test/batch_test.exs にデバッグコードを追加"
echo "3. lib/yesql/batch.ex のトランザクション処理を確認"
echo "4. 修正後、./scripts/run-local-ci.sh batch で確認"