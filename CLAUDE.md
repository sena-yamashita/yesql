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

### プッシュのタイミング
- **重要**: 自動的にプッシュしない
- ユーザーから明示的にプッシュの指示があった場合のみ実行
- CI/CDの負荷を考慮し、プッシュのタイミングはユーザーが制御

## 作業管理

### ToDo.md更新ルール
作業を完了した際は、必ずToDo.md（`docs/development/ToDo.md`）を更新してください：

1. **タスク完了時**
   - 完了したタスクにチェックマーク（✅）を付ける
   - 完了日を記載（例：`✅ タスク名（2025-07-26完了）`）
   - 関連する成果を「最近の成果」セクションに追加

2. **新規課題発見時**
   - 適切な優先度セクションに追加
   - 具体的で実行可能なタスクとして記載
   - 関連する既存タスクとの依存関係を明記

3. **進捗状況の更新**
   - 完了率の数値を更新
   - ドライバー実装状況テーブルを最新化
   - 次のステップを明確に記載

4. **更新タイミング**
   - 機能実装完了時
   - バグ修正完了時
   - ドキュメント作成・更新時
   - テスト追加・修正時
   - その他、プロジェクトの状態に変化があった時

## ドキュメント管理方針

すべてのドキュメントは`docs/`ディレクトリ配下で管理します。

### ディレクトリ構成

1. **ルートディレクトリ** (`/`)
   - プロジェクトの主要な説明文書のみ（README.md、CHANGELOG.md、CONTRIBUTING.md、RELEASE_NOTES.md）
   - Claude用の指示書（CLAUDE.md）

2. **docs/guides/** - ユーザー向けガイド
   - **configuration/** - 各データベースドライバーの設定ガイド
   - **features/** - 機能説明（ストリーミング、パラメータサポート等）
   - **examples/** - 使用例とサンプルコード

3. **docs/development/** - 開発者向けドキュメント
   - **architecture/** - システムアーキテクチャと設計文書
   - **internal/** - 内部仕様書、タスク管理
   - 本番環境チェックリスト等

4. **docs/troubleshooting/** - トラブルシューティング
   - 既知の問題と解決方法
   - FAQ
   - 外部プロジェクトでの問題解決

5. **docs/analysis/** - 技術分析・検討資料
   - 設計検討文書
   - パフォーマンス分析

### ファイル命名規則

- 英語またはローマ字表記を使用（内容は日本語可）
- スネークケース（snake_case）を使用
- 目的が明確にわかる名前を付ける

### 文書の分類

- **設定ガイド**: `docs/guides/configuration/*_configuration.md`
- **機能ガイド**: `docs/guides/features/*_guide.md` または `*_support.md`
- **使用例**: `docs/guides/examples/*_example.md`
- **トラブルシューティング**: `docs/troubleshooting/*_troubleshooting.md`
- **内部仕様**: `docs/development/internal/system_configuration_*.md`

### 新規ドキュメント作成時の注意

1. 必ず適切なディレクトリに配置する
2. 既存の命名規則に従う
3. 日本語で内容を記述する
4. 関連するドキュメントがある場合はリンクを追加する

## YesQLの設計原則

### 守るべき原則
1. **SQLファイルの内容をそのまま実行する** - SQL生成や改変は行わない
2. **パラメータ置換のみを行う** - :name を $1 に変換するなど、最小限の処理
3. **結果を適切に変換する** - データベースの結果をElixirのデータ構造に変換

### やってはいけないこと
1. **SQL文の自動生成** - BEGIN、COMMIT、CREATE TABLE等の生成
2. **ユーザーSQLの改変** - WITH句、ORDER BY、WHERE句の自動追加
3. **暗黙的なトランザクション管理** - ユーザーが明示的に制御すべき
4. **複雑なバッチ処理機能** - 単純なループで十分

### 設計思想
- YesQLは「SQLファイルをそのまま実行する」シンプルなツール
- SQL生成が必要な機能は別ライブラリとして分離を検討
- ユーザーがSQLを完全にコントロールできることが重要

## プロジェクト概要

- YesQLのマルチドライバー対応実装（v2.0.0）
- 現在サポート: PostgreSQL (Postgrex/Ecto), DuckDB
- プロトコルベースのドライバーアーキテクチャ
- 詳細な実装状態は `docs/development/internal/system_configuration_v2.md` を参照
- タスク管理は `docs/development/internal/ToDo.md` を参照

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
- 構成が変われば`docs/development/internal/system_configuration_v2.md`を必ず更新する

### 優先順位
1. 高：既存機能の安定性維持
2. 中：パフォーマンス最適化
3. 低：追加ドライバー対応（MySQL、MSSQL、Oracle）

## 外部ライブラリAPI使用時の注意

外部ライブラリのAPIを使用する際は、必ず以下を実施してください：

1. **ソースコードの確認** - GitHubで実際の実装を確認
2. **ドキュメントの確認** - hexdocsやREADMEで仕様を確認
3. **動作確認** - iexで実際に動作を確認

詳細は `docs/development/external_api_verification_checklist.md` を参照。

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

### GitHub CI確認方法

GitHub Actionsの実行状態を確認する際は、必ず`gh`コマンドを使用してください：

```bash
# 最近の実行状態を確認
gh api repos/sena-yamashita/yesql/actions/runs --jq '.workflow_runs[:5] | .[] | {id: .id, status: .status, conclusion: .conclusion, created_at: .created_at, name: .name}'

# 特定の実行の詳細を確認
gh run view <run_id>

# 失敗したジョブのログを確認
gh run view <run_id> --log-failed

# ワークフローの一覧を確認
gh workflow list

# 特定のワークフローの実行履歴
gh run list --workflow=<workflow_name>
```

**重要**: WebブラウザやWebSearchツールではなく、必ず`gh`コマンドを使用すること。これにより正確な情報を取得できます。

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

詳細な実装については `docs/development/internal/system_configuration_v2.md` を参照。

### 注意事項
- Elixir 1.18.4では、Ecto 3.5.xとの互換性問題あり
- Windows改行文字（\r\n）のサポートはv1.0.1で対応済み
- DuckDBテストは環境変数 `DUCKDB_TEST=true` で有効化

