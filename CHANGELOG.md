# 変更履歴

このプロジェクトの全ての注目すべき変更は、このファイルに記録されます。

フォーマットは[Keep a Changelog](https://keepachangelog.com/ja/1.0.0/)に基づいており、
このプロジェクトは[セマンティック バージョニング](https://semver.org/lang/ja/)に準拠しています。

## [2.0.0] - 2024-07-24

### 追加
- マルチドライバー対応のためのドライバー抽象化レイヤー（`Yesql.Driver`プロトコル）
- DuckDBドライバーサポート（`Yesql.Driver.DuckDB`）
- ドライバーファクトリー（`Yesql.DriverFactory`）による動的ドライバー作成
- DuckDB用テストスイート
- マルチドライバー対応のドキュメント（`guides/multi_driver_configuration.md`）
- 日本語ドキュメント（README.md、全てのガイド）
- プロジェクト管理ドキュメント（CLAUDE.md、SystemConfiguration.md、ToDo.md）

### 変更
- ドライバーサポートをハードコードから動的な仕組みに変更
- 既存のPostgrex/Ecto実装をプロトコル実装に移行
- `mix.exs`にleexコンパイラを追加
- テストヘルパーを拡張してDuckDBサポートを追加

### 技術的詳細
- **破壊的変更なし**: 既存のAPIは完全に互換性を維持
- **新しいドライバー形式**: `:postgrex`、`:ecto`、`:duckdb`のシンボル形式もサポート
- **依存関係**: DuckDBexを`optional: true`として追加

### 開発
- Claude Code (Anthropic)を使用したAIペアプログラミングによる実装
- 全コミットメッセージに`🤖 Generated with Claude Code`を含む

## [1.0.1] - 以前のリリース

### 修正
- Windows改行文字（\r\n）のサポート

### 詳細
オリジナルのリリース履歴については、[lpil/yesql](https://github.com/lpil/yesql)を参照してください。