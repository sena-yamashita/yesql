# 変更履歴

このプロジェクトの全ての注目すべき変更は、このファイルに記録されます。

フォーマットは[Keep a Changelog](https://keepachangelog.com/ja/1.0.0/)に基づいており、
このプロジェクトは[セマンティック バージョニング](https://semver.org/lang/ja/)に準拠しています。

## [2.1.2] - 2025-07-25

### 修正
- **DuckDBパラメータクエリの問題を修正**
  - 通常のクエリではネイティブパラメータバインディングを使用
  - ファイル関数（read_csv_auto等）では自動的に文字列置換を使用
  - DuckDBexの制限を回避する実装

### 改善
- **ドキュメントの再編成**
  - すべてのドキュメントを`docs/`ディレクトリ配下に集約
  - 体系的なディレクトリ構造（guides、development、troubleshooting、analysis）
  - CLAUDE.mdにドキュメント管理方針を明文化

## [2.1.1] - 2025-07-25

### 修正
- 外部プロジェクトでの依存関係コンパイルエラーを修正
  - application moduleの設定を削除
  - 条件付きコンパイルを全体に適用

## [2.1.0] - 2025-07-25

### 追加
- **ストリーミング結果セットのサポート** - 大規模データセットをメモリ効率的に処理
  - 統一的なストリーミングAPI（`Yesql.Stream`）
  - PostgreSQL: カーソルベースストリーミング（同期/非同期対応）
  - MySQL: サーバーサイドカーソル実装
  - DuckDB: Arrow形式とparallel scanningのサポート
  - SQLite: ステップ実行とFTS5対応
  - MSSQL: OFFSET/FETCHベースのページネーション実装
  - Oracle: REF CURSORとBULK COLLECTを活用
- ストリーミングガイド（`guides/streaming_guide.md`）
- 各ドライバー固有のストリーミング最適化
  - PostgreSQL: 非同期ストリーミング、統計情報収集
  - MySQL: パーティション並列処理、ファイルエクスポート
  - DuckDB: Parquetエクスポート、ウィンドウストリーミング
  - SQLite: メモリ最適化、インデックス活用
  - MSSQL: カーソルエミュレーション、一時テーブル活用
  - Oracle: In-Memory最適化、XMLTypeストリーミング

### 改善
- 全ドライバーでストリーミング機能が利用可能に
- ストリーミングテストスイートの追加
- README.mdにストリーミング使用例を追加
- Ectoドライバーとの比較分析ドキュメント（`analysis/ecto_vs_individual_drivers.md`）

## [2.0.0] - 2025-07-24

### 追加
- マルチドライバー対応のためのドライバー抽象化レイヤー（`Yesql.Driver`プロトコル）
- DuckDBドライバーサポート（`Yesql.Driver.DuckDB`）
- MySQL/MariaDBドライバーサポート（`Yesql.Driver.MySQL`）
- MSSQLドライバーサポート（`Yesql.Driver.MSSQL`）
- Oracleドライバーサポート（`Yesql.Driver.Oracle`）
- SQLiteドライバーサポート（`Yesql.Driver.SQLite`） - メモリDBもサポート
- バッチクエリ実行機能（`Yesql.Batch`）
- 改善されたトランザクション管理（`Yesql.Transaction`） - 分離レベル、セーブポイントのサポート
- ドライバーファクトリー（`Yesql.DriverFactory`）による動的ドライバー作成
- 各ドライバー用テストスイート
- パフォーマンスベンチマーク（`bench/`ディレクトリ）
- 各ドライバー設定ガイド（`guides/`ディレクトリ）
- v1.xからv2.0への移行ガイド（`guides/migration_guide.md`）
- 本番環境チェックリスト（`guides/production_checklist.md`）
- 日本語ドキュメント（README.md、全てのガイド）
- プロジェクト管理ドキュメント（CLAUDE.md、SystemConfiguration.md、ToDo.md、NewSystemConfiguration.md）

### 変更
- 最小Elixirバージョンを1.14に更新
- ドライバーサポートをハードコードから動的な仕組みに変更
- 既存のPostgrex/Ecto実装をプロトコル実装に移行
- `mix.exs`にleexコンパイラを追加（Mix.compilers()の使用を削除）
- テストヘルパーを拡張してDuckDB/MySQLサポートを追加
- config.exsでMix.ConfigからConfigモジュールに移行

### 技術的詳細
- **破壊的変更なし**: 既存のAPIは完全に互換性を維持
- **新しいドライバー形式**: `:postgrex`、`:ecto`、`:duckdb`、`:mysql`、`:mssql`、`:oracle`、`:sqlite`のシンボル形式もサポート
- **依存関係**: DuckDBex、MyXQL、Tds、jamdb_oracle、Exqliteを`optional: true`として追加
- **パフォーマンス**: 抽象化レイヤーのオーバーヘッドは約5-10μs

### 開発
- Claude Code (Anthropic)を使用したAIペアプログラミングによる実装
- 全コミットメッセージに`🤖 Generated with Claude Code`を含む

## [1.0.1] - 以前のリリース

### 修正
- Windows改行文字（\r\n）のサポート

### 詳細
オリジナルのリリース履歴については、[lpil/yesql](https://github.com/lpil/yesql)を参照してください。