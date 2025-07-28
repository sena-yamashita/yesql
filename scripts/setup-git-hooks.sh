#!/bin/bash
# Gitフックのセットアップスクリプト

echo "=== Git フックセットアップ ==="

# Gitフックディレクトリを設定
git config core.hooksPath .githooks

echo "✓ Gitフックが設定されました"
echo "  フックディレクトリ: .githooks/"
echo ""
echo "有効になったフック："
echo "  - pre-push: プッシュ前にテストとCIチェックを実行"
echo ""
echo "フックを無効にする場合："
echo "  git config --unset core.hooksPath"