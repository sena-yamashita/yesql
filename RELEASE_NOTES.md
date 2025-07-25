# Yesql リリースノート

## v2.1.2 (2025-07-25)

### 修正
- **DuckDBパラメータクエリの問題を修正**
  - 通常のクエリではネイティブパラメータバインディングを使用
  - ファイル関数（`read_csv_auto`等）では自動的に文字列置換を使用
  - DuckDBexの制限を透過的に回避

### 改善
- **ドキュメントの再編成**
  - すべてのドキュメントを`docs/`ディレクトリ配下に集約
  - 体系的なディレクトリ構造（guides、development、troubleshooting、analysis）
  - CLAUDE.mdにドキュメント管理方針を明文化
  - プロジェクト直下をクリーンアップ

### アップグレード方法
```elixir
{:yesql, "~> 2.1.2"}
```

## v2.1.1 (2025-07-25)

### 修正
- 外部プロジェクトでのコンパイルエラーを修正
  - アプリケーションモジュールを削除（ライブラリには不要）
  - 条件付きコンパイルを全てのドライバー依存コードに適用
  - 依存関係のバージョン制約を柔軟化（`>=` 形式）

### 改善
- オプショナル依存関係のサポートを強化
- 必要なドライバーのみをインストールして使用可能に
- より良いエラーメッセージ（ドライバーが利用できない場合）

## v2.1.0 (2025-07-25)

### 🎯 主な特徴

#### ストリーミング結果セットのサポート
全てのデータベースドライバーで大規模データセットをメモリ効率的に処理できるストリーミング機能を追加しました。

### 新機能
- **統一的なストリーミングAPI** (`Yesql.Stream`)
- **ドライバー別の最適化実装**:
  - PostgreSQL: カーソルベース（同期/非同期対応）
  - MySQL: サーバーサイドカーソル
  - DuckDB: Arrow形式、並列スキャン
  - SQLite: ステップ実行、FTS5対応
  - MSSQL: ページネーション、カーソルエミュレーション
  - Oracle: REF CURSOR、BULK COLLECT

### 使用例
```elixir
# 大規模データのストリーミング処理
{:ok, stream} = Yesql.Stream.query(conn,
  "SELECT * FROM large_table WHERE created_at > $1",
  [~D[2024-01-01]],
  driver: :postgrex,
  chunk_size: 1000
)

stream
|> Stream.map(&process_row/1)
|> Stream.filter(&valid?/1)
|> Enum.count()
```

### ドキュメント
- [ストリーミングガイド](guides/streaming_guide.md)を追加
- Ectoドライバーとの比較分析ドキュメントを追加

## v2.0.0 (2024-07-24)

このリリースは、オリジナルの[lpil/yesql](https://github.com/lpil/yesql) v1.0.1からフォークし、マルチドライバー対応を追加した最初のメジャーリリースです。

## 🎯 主な特徴

### マルチドライバー対応
新しいドライバー抽象化レイヤーにより、複数のデータベースドライバーを簡単に切り替えて使用できるようになりました。

### サポートドライバー
- **Postgrex** - PostgreSQL（既存）
- **Ecto** - Ectoリポジトリ（既存）
- **DuckDB** - 分析用データベース（新規）✨

## 📋 変更内容

### 新機能
- `Yesql.Driver`プロトコルによるドライバー抽象化
- `Yesql.DriverFactory`による動的ドライバー作成
- DuckDBドライバーの実装（DuckDBex使用）
- マルチドライバー対応のテストスイート
- 包括的な日本語ドキュメント

### 技術的改善
- ハードコードされたドライバーサポートを動的な仕組みに変更
- 既存のPostgrex/Ecto実装をプロトコル実装に移行
- より拡張可能なアーキテクチャ

### ドキュメント
- 全てのドキュメントを日本語化
- マルチドライバー設定ガイドの追加
- プロジェクト管理ドキュメント（CLAUDE.md、SystemConfiguration.md）

## 💻 使用例

### DuckDBの使用
```elixir
defmodule Analytics do
  use Yesql, driver: :duckdb

  {:ok, db} = Duckdbex.open("analytics.duckdb")
  {:ok, conn} = Duckdbex.connection(db)

  Yesql.defquery("analytics/aggregate_sales.sql")
  
  Analytics.aggregate_sales(conn, start_date: "2024-01-01")
end
```

### ドライバーの動的切り替え
```elixir
defmodule MyApp.Queries do
  use Yesql
  
  # PostgreSQL用
  Yesql.defquery("queries/users.sql", driver: :postgrex)
  
  # DuckDB用（分析クエリ）
  Yesql.defquery("queries/analytics.sql", driver: :duckdb)
end
```

## 🔧 インストール

```elixir
def deps do
  [
    {:yesql, "~> 2.0.0"},
    # オプション：必要なドライバーのみ追加
    {:postgrex, "~> 0.15", optional: true},
    {:ecto, "~> 3.4", optional: true},
    {:duckdbex, "~> 0.3.9", optional: true}
  ]
end
```

## ⚠️ 注意事項

- **後方互換性**: 既存のAPIは完全に維持されています
- **DuckDBテスト**: `DUCKDB_TEST=true mix test`で実行

## 🙏 謝辞

- オリジナルの作者 [Louis Pilfold](https://github.com/lpil) に感謝
- このマルチドライバー対応は[Claude Code](https://claude.ai/code)を使用して開発されました

## 👥 貢献者

- **Daisuke Yamashita** (SENA Networks, Inc.) - マルチドライバー対応の設計と実装
- **Claude Code** (Anthropic) - AIペアプログラミングツールとしての開発支援

## 📄 ライセンス

Apache License 2.0（オリジナルと同じ）

---

詳細な変更内容は[CHANGELOG.md](CHANGELOG.md)を参照してください。