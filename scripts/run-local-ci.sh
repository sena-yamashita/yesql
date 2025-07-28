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
