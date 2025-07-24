# Yesql v2.0.0 リリースノート

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