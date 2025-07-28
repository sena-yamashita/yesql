# act設定ディレクトリ

このディレクトリはact（GitHub Actionsのローカル実行ツール）用の設定を管理します。

## ディレクトリ構成

- `workflows/` - act専用のワークフロー（GitHub Actionsでは実行されない）
  - `test.yml` - 基本的なテスト（PostgreSQL付き）
  - `act-test.yml` - シンプルなテスト（コンテナ環境）
  - `local-ci-test.yml` - 完全なCI環境の再現
- `env` - 環境変数設定
- `secrets` - シークレット設定（.gitignoreに含まれる）

## 使用方法

### act専用ワークフローの実行
```bash
# 基本的なテスト
act -W .act/workflows/test.yml

# シンプルなテスト（高速）
act -W .act/workflows/act-test.yml

# 完全なCI環境の再現
act -W .act/workflows/local-ci-test.yml
```

### 本番ワークフローのローカル実行
```bash
# GitHub Actionsのワークフローをローカルで実行
act -W .github/workflows/elixir.yml
act -W .github/workflows/ci.yml
```

## 注意事項

- `.act/workflows/`内のファイルはGitHub Actionsでは実行されません
- ローカル開発・デバッグ専用です
- 本番用のワークフローは`.github/workflows/`に配置してください