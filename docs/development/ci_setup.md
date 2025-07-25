# GitHub Actions CI セットアップガイド

## 概要

YesqlプロジェクトでGitHub Actionsを使用した継続的インテグレーション（CI）を設定するためのガイドです。

## CI設定ファイル

プロジェクトには3つのGitHub Actionsワークフローが設定されています：

### 1. `.github/workflows/ci.yml` - 総合CIワークフロー

主要なCIパイプラインで、以下を実行します：

- **マトリックステスト**: 複数のElixir/OTPバージョンでテスト
  - Elixir: 1.14, 1.15, 1.16
  - OTP: 25, 26
  
- **データベーステスト**: 各データベースサービスでテスト
  - PostgreSQL 15
  - MySQL 8.0
  - MSSQL 2022
  - SQLite（組み込み）
  - DuckDB（別ジョブ）

- **コード品質チェック**:
  - フォーマットチェック（`mix format --check-formatted`）
  - Dialyzer（静的解析）

### 2. `.github/workflows/elixir.yml` - シンプルなElixir CI

基本的なElixirプロジェクトのCIで、以下を実行：

- 依存関係のインストール
- コンパイル（警告をエラーとして扱う）
- テストの実行
- コード品質チェック（format、credo）

### 3. `.github/workflows/database-tests.yml` - データベース個別テスト

各データベースドライバーを個別にテスト：

- PostgreSQL（Dockerサービス使用）
- MySQL（Dockerサービス使用）
- SQLite（ファイルベース）
- DuckDB（NIF コンパイル含む）
- MSSQL（Dockerサービス使用）

## 使用方法

### 1. ワークフローの有効化

これらのファイルを`.github/workflows/`ディレクトリに配置すると、GitHub Actionsが自動的に有効になります。

### 2. トリガー条件

ワークフローは以下の条件でトリガーされます：

- `master`、`main`、`dev`ブランチへのプッシュ
- これらのブランチへのプルリクエスト

### 3. 必要な設定

特別な設定は不要です。GitHub Actionsはリポジトリのデフォルト設定で動作します。

## ローカルでのテスト

CIと同じ環境でローカルテストを実行するには：

```bash
# 全テスト実行
mix test

# PostgreSQLテストのみ
mix test test/postgrex_test.exs

# DuckDBテストのみ（要環境変数）
DUCKDB_TEST=true mix test test/duckdb_test.exs

# フォーマットチェック
mix format --check-formatted
```

## テスト環境変数

各データベースドライバーのテストには以下の環境変数が使用されます：

### PostgreSQL
```bash
POSTGRES_HOST=localhost
POSTGRES_PORT=5432
POSTGRES_USER=postgres
POSTGRES_PASSWORD=postgres
POSTGRES_DATABASE=yesql_test
```

### MySQL
```bash
MYSQL_HOST=localhost
MYSQL_PORT=3306
MYSQL_USER=root
MYSQL_PASSWORD=root
MYSQL_DATABASE=yesql_test
MYSQL_TEST=true
```

### DuckDB
```bash
DUCKDB_TEST=true
```

### SQLite
```bash
SQLITE_TEST=true
```

### MSSQL
```bash
MSSQL_HOST=localhost
MSSQL_PORT=1433
MSSQL_USER=sa
MSSQL_PASSWORD=YourStrong@Passw0rd
MSSQL_DATABASE=master
MSSQL_TEST=true
```

## トラブルシューティング

### DuckDBexのコンパイルエラー

DuckDBはC++で書かれたNIFを使用するため、ビルドツールが必要です：

```bash
# Ubuntu/Debian
sudo apt-get install build-essential cmake

# macOS
brew install cmake
```

### データベース接続エラー

CIではDockerコンテナでデータベースサービスを起動します。ローカルでは適切なデータベースサーバーが必要です。

### キャッシュの問題

依存関係やPLTキャッシュに問題がある場合、GitHubのActions設定からキャッシュをクリアできます。

## 推奨事項

1. **ワークフローの選択**: 
   - 小規模な変更には`elixir.yml`
   - データベース機能の変更には`database-tests.yml`
   - リリース前の総合テストには`ci.yml`

2. **テストの分離**: 各データベースドライバーのテストは独立して実行可能

3. **並列実行**: 異なるデータベースのテストは並列で実行され、時間を節約

## 今後の改善案

- Oracle データベースのCIサポート追加
- ベンチマークテストの自動実行
- カバレッジレポートの生成
- リリースの自動化