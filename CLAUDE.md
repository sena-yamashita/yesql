# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

このファイルは、このリポジトリでコードを扱う際のClaude Code (claude.ai/code)への指針を提供します。

## 会話

- 常に日本語で会話する
- 会話は常に日本語を使用してください
- 説明、コメント、エラーメッセージなども日本語で記述

## Git管理

### コミットのタイミング
以下の条件を満たした場合、自動的にgit commitを実行してください：

1. **機能の実装が完了**
   - 新機能の実装が完了し、コンパイルが通る
   - テストが通る（cargo testを実行）
   - 意味のある変更のまとまりができた

2. **大きな変更の区切り**
   - ファイル構造の変更
   - 重要なバグ修正
   - パフォーマンス改善の実装

3. **作業セッションの終了時**
   - ユーザーから「ありがとう」「お疲れ様」などの終了を示唆する言葉があった場合

### コミットメッセージの形式
```
<type>: <subject>

<body>

🤖 Generated with [Claude Code](https://claude.ai/code)

Co-Authored-By: Claude <noreply@anthropic.com>
```

**type**:
- feat: 新機能
- fix: バグ修正
- docs: ドキュメントのみの変更
- style: コードの意味に影響しない変更（空白、フォーマット等）
- refactor: バグ修正や機能追加を伴わないコード変更
- perf: パフォーマンス改善
- test: テストの追加や修正
- chore: ビルドプロセスやツールの変更

### 自動プッシュ
- コミット後、必ず自動的にpushを実行
- 外部プロジェクトから依存関係として参照される可能性があるため、常に最新の状態を保つ

## ドキュメント管理方針

新しいドキュメントを作成する際は、以下の方針に従ってください：

### ディレクトリ構成

1. **ルートディレクトリ** (`/`)
   - プロジェクトの主要な説明文書（README.md、CHANGELOG.md、CONTRIBUTING.md等）
   - 開発者向けの内部管理文書（CLAUDE.md、SystemConfiguration.md等）

2. **guides/** 
   - ユーザー向けの設定・使用ガイド
   - 機能説明（ストリーミング、マルチドライバー等）
   - 実装例やサンプルコード

3. **troubleshooting/** （必要に応じて作成）
   - トラブルシューティングガイド
   - 既知の問題と解決方法
   - FAQ

4. **analysis/**
   - 技術分析文書
   - 設計検討資料

### ファイル命名規則

- 英語またはローマ字表記を使用（内容は日本語可）
- スネークケース（snake_case）またはケバブケース（kebab-case）を使用
- 目的が明確にわかる名前を付ける

### 文書の分類

- **設定ガイド**: `guides/*_configuration.md`
- **使用ガイド**: `guides/*_guide.md`
- **トラブルシューティング**: `troubleshooting/*_troubleshooting.md`
- **分析・検討**: `analysis/*_analysis.md`

### 既存ドキュメントの移動

新しい方針に合わないドキュメントを発見した場合は、適切なディレクトリに移動してください。

## プロジェクト概要

- YesQLのマルチドライバー対応実装（v2.0.0）
- 現在サポート: PostgreSQL (Postgrex/Ecto), DuckDB
- プロトコルベースのドライバーアーキテクチャ
- 詳細な実装状態は `NewSystemConfiguration.md` を参照
- タスク管理は `ToDo.md` を参照

## 今後の開発方針
- Elixirは1.14でも動くようにしてください。
- 追加ドライバー対応を行っていきます。
   - MySQL/MariaDB
   - MSSQL
   - Oracle

### 新規ドライバー追加手順
1. `lib/yesql/driver/` にドライバーモジュールを作成
2. `Yesql.Driver` プロトコルを実装
3. `Yesql.DriverFactory` に追加
4. テストスイートを `test/drivers/` に追加
5. ドキュメントを更新

### コード品質の維持
- すべての変更にはテストを含める
- 既存APIの後方互換性を維持
- パフォーマンスへの影響を考慮
- 構成が変わればNewSystemConfiguration.mdを必ず更新する

### 優先順位
1. 高：既存機能の安定性維持
2. 中：パフォーマンス最適化
3. 低：追加ドライバー対応（MySQL、MSSQL、Oracle）

## 参考

- オリジナルフォーク元: https://github.com/lpil/yesql
- 参考実装: https://github.com/tschnibo/yesql/tree/dev

## 開発コマンド

### ビルドとテスト
```bash
# 依存関係の取得
mix deps.get

# コンパイル
mix compile

# テストの実行（PostgreSQLが必要）
mix test

# DuckDBテストの実行
DUCKDB_TEST=true mix test test/duckdb_test.exs

# 自動テスト（ファイル変更を監視）
mix test.watch

# ドキュメント生成
mix docs

# インタラクティブシェル
iex -S mix
```

### データベース設定
テスト実行にはPostgreSQLデータベース `yesql_test` が必要です：
```bash
createdb yesql_test
```

## 技術詳細

### プロジェクト構成
- **言語**: Elixir（Erlang VM上で動作）
- **ビルドツール**: Mix
- **最小Elixirバージョン**: 1.14以上
- **テストフレームワーク**: ExUnit

### アーキテクチャ概要
- **プロトコルベースのドライバーシステム**: `Yesql.Driver`
- **動的ドライバー作成**: `Yesql.DriverFactory`
- **SQLトークナイザー**: Leexを使用した名前付きパラメータ解析
- **コンパイル時マクロ**: `defquery`による関数生成

詳細な実装については `NewSystemConfiguration.md` を参照。

### 注意事項
- Elixir 1.18.4では、Ecto 3.5.xとの互換性問題あり
- Windows改行文字（\r\n）のサポートはv1.0.1で対応済み
- DuckDBテストは環境変数 `DUCKDB_TEST=true` で有効化

