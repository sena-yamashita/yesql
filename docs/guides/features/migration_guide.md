# YesQL v1.x から v2.0 への移行ガイド

このガイドでは、YesQL v1.xからv2.0への移行方法を説明します。

## 概要

YesQL v2.0は後方互換性を維持しながら、マルチドライバー対応を追加しました。既存のコードはそのまま動作しますが、新機能を活用するためにいくつかの推奨事項があります。

## 主な変更点

### 1. マルチドライバー対応
- PostgreSQL以外に、DuckDB、MySQL、MSSQL、Oracle、SQLiteをサポート
- プロトコルベースのドライバーアーキテクチャ

### 2. Elixir最小バージョン
- v1.x: Elixir 1.7以上
- v2.0: Elixir 1.14以上

### 3. 新しいドライバー指定方法
- アトム形式（`:postgrex`）での指定を推奨
- モジュール形式（`Postgrex`）も引き続きサポート

## 移行手順

### ステップ1: 依存関係の更新

```elixir
# mix.exs

# v1.x
defp deps do
  [
    {:yesql, "~> 1.0"},
    {:postgrex, "~> 0.15"}
  ]
end

# v2.0
defp deps do
  [
    {:yesql, "~> 2.0"},
    {:postgrex, "~> 0.15"},  # または最新版
    # 必要に応じて他のドライバーを追加
    {:myxql, "~> 0.6", optional: true},
    {:duckdbex, "~> 0.3.9", optional: true}
  ]
end
```

### ステップ2: コードの更新（オプション）

既存のコードはそのまま動作しますが、新しい記法への更新を推奨します：

```elixir
# v1.x（引き続き動作）
defmodule MyApp.Queries do
  use Yesql, driver: Postgrex, conn: MyApp.Repo
  
  Yesql.defquery("queries/users.sql")
end

# v2.0（推奨）
defmodule MyApp.Queries do
  use Yesql, driver: :postgrex, conn: MyApp.Repo
  
  Yesql.defquery("queries/users.sql")
end
```

### ステップ3: 新機能の活用

#### 複数ドライバーの使用

```elixir
# PostgreSQL用クエリ
defmodule MyApp.PostgresQueries do
  use Yesql, driver: :postgrex
  Yesql.defquery("queries/postgres/users.sql")
end

# MySQL用クエリ
defmodule MyApp.MySQLQueries do
  use Yesql, driver: :mysql
  Yesql.defquery("queries/mysql/users.sql")
end

# DuckDB用分析クエリ
defmodule MyApp.Analytics do
  use Yesql, driver: :duckdb
  Yesql.defquery("queries/analytics/reports.sql")
end
```

## 互換性の詳細

### 完全に互換性のある部分

1. **API**: 全ての既存APIはそのまま使用可能
2. **SQLファイル形式**: 変更なし
3. **パラメータ形式**: PostgreSQL/Ectoは`$1, $2...`形式を維持
4. **結果形式**: マップのリストとして返却

### 注意が必要な部分

1. **Elixirバージョン**: 1.14未満の環境では動作しません
2. **Mix.compilers()**: v2.0では自動的に対応済み
3. **config/config.exs**: `use Mix.Config`は`import Config`に変更推奨

## トラブルシューティング

### コンパイルエラー

```elixir
# エラー: Mix.compilers/0 is deprecated
# 解決: mix.exsを確認し、以下のように修正

# 変更前
compilers: [:leex] ++ Mix.compilers()

# 変更後
compilers: [:leex]
```

### ドライバーが見つからない

```elixir
# エラー: {:error, :driver_not_loaded}
# 解決: 必要なドライバーの依存関係を追加

defp deps do
  [
    {:yesql, "~> 2.0"},
    {:postgrex, "~> 0.15"},    # PostgreSQL
    {:myxql, "~> 0.6"},        # MySQL
    {:duckdbex, "~> 0.3.9"}    # DuckDB
  ]
end
```

### 設定ファイルの警告

```elixir
# 警告: Mix.Config.config/2 is deprecated
# 解決: config/config.exsを更新

# 変更前
use Mix.Config

# 変更後
import Config
```

## ベストプラクティス

### 1. ドライバー別のモジュール分離

```elixir
# lib/my_app/queries/
# ├── postgres.ex
# ├── mysql.ex
# └── analytics.ex

defmodule MyApp.Queries.Postgres do
  use Yesql, driver: :postgrex
  # PostgreSQL固有のクエリ
end

defmodule MyApp.Queries.MySQL do
  use Yesql, driver: :mysql
  # MySQL固有のクエリ
end
```

### 2. 環境別の設定

```elixir
# config/dev.exs
config :my_app, :database_driver, :sqlite

# config/prod.exs
config :my_app, :database_driver, :postgrex

# 実行時に選択
driver = Application.get_env(:my_app, :database_driver)
```

### 3. SQLファイルの整理

```
queries/
├── postgres/
│   ├── users.sql
│   └── reports.sql
├── mysql/
│   ├── users.sql
│   └── reports.sql
└── common/
    └── shared_queries.sql
```

## 移行チェックリスト

- [ ] Elixir 1.14以上にアップグレード
- [ ] mix.exsでyesqlを`~> 2.0`に更新
- [ ] 必要なドライバーの依存関係を追加
- [ ] `mix deps.get`を実行
- [ ] アプリケーションをコンパイル・テスト
- [ ] （オプション）ドライバー指定をアトム形式に更新
- [ ] （オプション）config.exsで`import Config`を使用
- [ ] （オプション）新しいドライバーの活用を検討

## サポート

移行に関する質問や問題がある場合は、[GitHubのIssue](https://github.com/tschnibo/yesql/issues)で報告してください。