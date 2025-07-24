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
- コミット後、ユーザーが要求した場合のみpushを実行
- または、作業セッション終了時にユーザーに確認してからpush

## 作業管理

ToDo.mdを作成し、ToDoの内容、状況、進捗、残件、課題を管理するようにしてください。

## 概要

- 現状のyesqlを複数のドライバが対応できるようにカスタマイズする
- まず、しっかりと既存のコードを把握するようにしてください。
- 把握した内容は、SystemConfiguration.mdに記載をしてください。
- その後、duckdb対応をする。
- duckdb利用ドライバは、https://github.com/AlexR2D2/duckdbex を利用する。
- 今後、MySQLや、MSSQL、Oracle等のドライバを対応していく。優先度最低

## 参考

https://github.com/tschnibo/yesql/tree/dev

## 開発コマンド

### ビルドとテスト
```bash
# 依存関係の取得
mix deps.get

# コンパイル
mix compile

# テストの実行（PostgreSQLが必要）
mix test

# 特定のテストファイルを実行
mix test test/yesql_test.exs

# 特定のテストケースを実行（行番号指定）
mix test test/yesql_test.exs:42

# インタラクティブシェル
iex -S mix
```

### データベース設定
テスト実行にはPostgreSQLデータベース `yesql_test` が必要です：
```bash
createdb yesql_test
```

## アーキテクチャ概要

### コア構造
- **lib/yesql.ex**: メインモジュール、`defquery`マクロを提供
- **lib/yesql/tokenizer.ex**: SQLファイルのトークナイザー（Leex使用）
- **src/sql_tokenizer.xrl**: Leexトークナイザー定義ファイル

### 主要な抽象化
1. **SQLトークナイザー**: SQLファイルを解析し、名前付きパラメータ（`:name`）を検出
2. **パラメータ変換**: 名前付きパラメータをデータベース固有の形式に変換
   - PostgreSQL: `:name` → `$1`, `$2`...
   - DuckDB対応時: 適切な形式への変換が必要
3. **結果変換**: データベースの結果をElixirのデータ構造に変換

### 現在の制限事項
- ドライバーサポートがハードコード（`@supported_drivers [:postgrex, :ecto]`）
- ドライバー固有のロジックが`yesql.ex`に直接実装
- 新しいドライバー追加には大幅なリファクタリングが必要

### DuckDB対応の方針
1. ドライバーインターフェースの抽象化（プロトコルまたはビヘイビア）
2. DuckDBexドライバーの統合
3. パラメータ変換ロジックの拡張
4. 結果セット変換の実装

## 技術詳細

### プロジェクト構成
- **言語**: Elixir（Erlang VM上で動作）
- **ビルドツール**: Mix
- **最小Elixirバージョン**: 1.5以上
- **テストフレームワーク**: ExUnit

### 開発コマンド
```bash
# 依存関係のインストール
mix deps.get

# テストの実行（PostgreSQLが必要）
createdb yesql_test
mix test

# 自動テスト（ファイル変更を監視）
mix test.watch

# ドキュメント生成
mix docs

# コンパイル
mix compile
```

### 現在のアーキテクチャ
詳細は `SystemConfiguration.md` を参照してください。主要ポイント：
- SQLトークナイザー（Leex使用）でSQLファイルを解析
- コンパイル時にマクロでElixir関数を生成
- 現在サポートドライバー: Postgrex, Ecto
- ドライバー実装がハードコードされている

### DuckDB対応で必要な主要変更
1. ドライバーインターフェースの抽象化（ビヘイビアまたはプロトコル）
2. ドライバー固有のパラメータ変換ロジック
3. 結果セット変換の柔軟化
4. DuckDBexライブラリの統合

### 注意事項
- Elixir 1.18.4では、Ecto 3.5.xとの互換性問題あり
- Windows改行文字（\r\n）のサポートはv1.0.1で対応済み

