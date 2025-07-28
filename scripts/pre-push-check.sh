#!/bin/bash
# プッシュ前のデグレード防止チェックスクリプト

set -e

echo "=== YesQL プッシュ前チェック ==="
echo "デグレード防止のため、以下のチェックを実行します："
echo ""

# カラー定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# チェック結果を記録
CHECKS_PASSED=true

# 1. コードフォーマットチェック
echo "1. コードフォーマットチェック..."
if mix format --check-formatted; then
    echo -e "${GREEN}✓ コードフォーマット: PASS${NC}"
else
    echo -e "${RED}✗ コードフォーマット: FAIL${NC}"
    echo "  実行してください: mix format"
    CHECKS_PASSED=false
fi
echo ""

# 2. コンパイルチェック
echo "2. コンパイルチェック..."
if mix compile --warnings-as-errors; then
    echo -e "${GREEN}✓ コンパイル: PASS${NC}"
else
    echo -e "${RED}✗ コンパイル: FAIL${NC}"
    CHECKS_PASSED=false
fi
echo ""

# 3. ローカルテスト (make test-all)
echo "3. ローカルテスト実行 (make test-all)..."
echo -e "${YELLOW}   注意: Dockerコンテナが起動します${NC}"
if make test-all; then
    echo -e "${GREEN}✓ ローカルテスト: PASS${NC}"
else
    echo -e "${RED}✗ ローカルテスト: FAIL${NC}"
    echo "  ヒント: make docker-logs でログを確認"
    CHECKS_PASSED=false
fi
echo ""

# 4. act（ローカルCI）チェック
if command -v act &> /dev/null; then
    echo "4. ローカルCI (act) チェック..."
    echo "   重要なワークフローをチェックします..."
    
    # Elixir CIワークフローをチェック
    if act -W .github/workflows/elixir.yml -j test --dryrun > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Elixir CI設定: 有効${NC}"
        
        # 実際に実行するか確認
        echo -e "${YELLOW}   Elixir CIを実行しますか？ (時間がかかります) [y/N]${NC}"
        read -r response
        if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
            if act -W .github/workflows/elixir.yml -j test -P ubuntu-latest=catthehacker/ubuntu:act-latest; then
                echo -e "${GREEN}✓ Elixir CI: PASS${NC}"
            else
                echo -e "${RED}✗ Elixir CI: FAIL${NC}"
                CHECKS_PASSED=false
            fi
        else
            echo -e "${YELLOW}⚠ Elixir CI: スキップされました${NC}"
        fi
    else
        echo -e "${YELLOW}⚠ Elixir CI設定に問題がある可能性があります${NC}"
    fi
else
    echo -e "${YELLOW}⚠ actがインストールされていません${NC}"
    echo "  インストール方法: brew install act (macOS) または公式ドキュメントを参照"
fi
echo ""

# 5. Dialyzer警告チェック（オプション）
echo "5. Dialyzer警告チェック..."
echo -e "${YELLOW}   Dialyzerを実行しますか？ (時間がかかります) [y/N]${NC}"
read -r response
if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    if mix dialyzer; then
        echo -e "${GREEN}✓ Dialyzer: PASS${NC}"
    else
        echo -e "${YELLOW}⚠ Dialyzer: 警告あり（必須ではありません）${NC}"
    fi
else
    echo -e "${YELLOW}⚠ Dialyzer: スキップされました${NC}"
fi
echo ""

# 結果表示
echo "=== チェック結果 ==="
if [ "$CHECKS_PASSED" = true ]; then
    echo -e "${GREEN}✓ すべての必須チェックがPASSしました！${NC}"
    echo ""
    echo "安全にプッシュできます："
    echo "  git push origin $(git branch --show-current)"
    exit 0
else
    echo -e "${RED}✗ 一部のチェックが失敗しました${NC}"
    echo ""
    echo "プッシュ前に上記の問題を修正してください。"
    echo "強制的にプッシュする場合（推奨しません）："
    echo "  git push origin $(git branch --show-current) --no-verify"
    exit 1
fi