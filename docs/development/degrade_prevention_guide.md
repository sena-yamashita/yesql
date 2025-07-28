# デグレード防止ガイド

## 概要
コードの品質を保ち、デグレードを防ぐための仕組みとガイドラインです。

## 必須チェック項目

### 1. プッシュ前チェックの実行
```bash
./scripts/pre-push-check.sh
```

このスクリプトは以下を自動的にチェックします：

#### 必須項目
- ✅ **コードフォーマット** - `mix format --check-formatted`
- ✅ **コンパイル** - `mix compile --warnings-as-errors`
- ✅ **ローカルテスト** - `make test-all`

#### オプション項目
- ⚠️ **ローカルCI (act)** - GitHub Actionsと同じ環境でテスト
- ⚠️ **Dialyzer** - 型チェックと静的解析

### 2. Gitフックの設定

自動化のためにGitフックを設定することを推奨：

```bash
./scripts/setup-git-hooks.sh
```

これにより、`git push`時に自動的にチェックが実行されます。

### 3. 手動プッシュ時の確認

プッシュする前に必ず以下を確認：

1. **make test-all がPASS**
   ```bash
   make test-all
   ```

2. **actでCI環境を再現（推奨）**
   ```bash
   # Elixir CIを実行
   act -W .github/workflows/elixir.yml -P ubuntu-latest=catthehacker/ubuntu:act-latest
   ```

3. **コードフォーマット**
   ```bash
   mix format
   ```

## チェックをスキップする場合（非推奨）

緊急時のみ、チェックをスキップできます：

```bash
git push origin main --no-verify
```

⚠️ **警告**: デグレードのリスクがあるため、通常は使用しないでください。

## CI環境での問題対応

### 1. ローカルでの再現

CI環境特有の問題がある場合、actを使用して再現：

```bash
# BatchTestのデバッグ
act -W .github/workflows/batch-test-debug.yml

# Database Tests
act -W .github/workflows/ci.yml
```

### 2. デバッグスクリプト

特定のテストをデバッグ：

```bash
# BatchTestのデバッグ
./scripts/debug-batch-test.sh
```

## トラブルシューティング

### actがインストールされていない
```bash
# macOS
brew install act

# Linux
curl -s https://raw.githubusercontent.com/nektos/act/master/install.sh | sudo bash
```

### Dockerメモリ不足
Docker Desktop → Settings → Resources → Memory: 8GB以上に設定

### make test-allが失敗
1. Dockerサービスが起動しているか確認
2. `docker-compose.yml`の設定を確認
3. `make docker-logs`でログを確認

## ベストプラクティス

1. **頻繁にチェックを実行**
   - 大きな変更の前後で実行
   - コミット前に実行

2. **CI環境の事前確認**
   - actでローカルCI実行
   - 問題があれば事前に修正

3. **チームでの共有**
   - 全員がGitフックを設定
   - チェック項目を理解

## 関連ドキュメント

- [ローカルCI環境セットアップ](./local_ci_setup.md)
- [CIトラブルシューティング](./ci_troubleshooting.md)
- [CLAUDE.md](/CLAUDE.md#デグレード防止必須)