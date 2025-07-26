# Yesql ToDo リスト

最終更新: 2025-07-26

## 🎯 プロジェクト全体の状況

### ✅ 完了済みタスク
- DuckDBドライバーの実装と統合
- 全ドライバーのストリーミング機能実装（Ecto以外）
- コンパイル警告の解消
- CIエラーの修正
- DuckDBストリーミングのfetch_chunk対応

### 📊 ドライバー実装状況
| ドライバー | 基本機能 | ストリーミング | テスト | 状態 |
|-----------|---------|--------------|--------|------|
| PostgreSQL | ✅ | ✅ | ❌ | 安定 |
| Ecto | ✅ | ❌ | ❌ | 基本機能のみ |
| DuckDB | ✅ | ✅ | ✅ | 高度な機能付き |
| MySQL | ✅ | ✅ | ✅ | 安定 |
| SQLite | ✅ | ✅ | ✅ | 安定 |
| MSSQL | ✅ | ✅ | ✅ | 安定 |
| Oracle | ✅ | ✅ | ✅ | 安定 |

## 🚨 高優先度タスク

### 1. YesQL設計思想の遵守
- [ ] **SQL生成機能の削除または分離**
  - [ ] DuckDBStream: create_windowed_stream（WITH句自動追加）
  - [ ] DuckDBStream: create_aggregation_stream（一時テーブル自動作成）
  - [ ] DuckDBStream: export_to_parquet（COPY TO文自動生成）
  - [ ] DuckDBStream: create_parallel_scan（WHERE句/LIMIT/OFFSET自動追加）
  - [ ] Yesql.Transaction: BEGIN/COMMIT/ROLLBACK自動生成
  - [ ] Yesql.Batch: トランザクション自動管理
- [ ] **別ライブラリへの分離検討**
  - これらの機能は`yesql-helpers`のような別パッケージに

### 2. テストの充実
- [ ] **PostgreSQLドライバーの専用テスト作成**
- [ ] **Ectoドライバーの専用テスト作成**
- [ ] **統合テストの作成**
  - 全ドライバー共通の動作確認
  - パフォーマンス比較

## 📝 中優先度タスク

### 3. Ectoストリーミング実装
- [ ] Ecto.Streamを活用したストリーミング機能
- [ ] Repo.streamとの統合
- [ ] トランザクション内でのストリーミング対応

### 4. エラーハンドリングの改善
- [ ] 統一的なエラー型の定義
- [ ] より詳細なエラーメッセージ
- [ ] SQLファイル不在時の分かりやすいエラー
- [ ] パラメータ不足時の具体的な指示

### 5. パフォーマンス最適化
- [ ] ETSキャッシュのTTL実装
- [ ] メモリ使用量の監視機構
- [ ] 大規模データセットでのベンチマーク

## 💡 機能改善案

### 6. ドキュメントの充実
- [ ] 各ドライバーの詳細な使用方法
- [ ] ストリーミングAPIのベストプラクティス
- [ ] パフォーマンスチューニングガイド
- [ ] 移行ガイド（他のSQLライブラリから）

### 7. 開発者体験の向上
- [ ] より良いデバッグ情報
- [ ] SQLファイルのホットリロード（開発環境）
- [ ] Visual Studio Code拡張の作成
- [ ] mix yesql.gen.queryタスクの作成

### 8. 互換性の向上
- [ ] Ecto 3.13以降の新機能対応
- [ ] OTP 26のサポート確認
- [ ] 新しいデータベースドライバーの追加検討
  - [ ] ClickHouse
  - [ ] CockroachDB
  - [ ] TimescaleDB

## 🔧 技術的改善

### 9. コード品質
- [ ] Dialyzerの完全対応
- [ ] Credo設定の追加
- [ ] ExCoverallsでのカバレッジ測定
- [ ] プロパティベーステストの追加

### 10. CI/CD改善
- [ ] データベース統合テストの自動化
- [ ] パフォーマンス回帰テスト
- [ ] 自動リリース設定

## 📌 現在の制限事項と対策

### DuckDBストリーミング
- ✅ ~~fetch_allによる全データ取得~~ → fetch_chunkで解決済み
- DuckDBexのチャンクサイズは約2048行固定

### 各ドライバーの制限
- **Ecto**: ストリーミング未実装
- **PostgreSQL/Ecto**: 専用テスト不足
- **全般**: JSON処理の依存性が未解決

## 🎯 次のステップ

1. **YesQL設計思想の遵守**を最優先で実施
2. PostgreSQL/Ectoのテスト作成
3. Ectoストリーミング実装
4. ドキュメントの充実

## 📚 参考資料

- [YesQL設計原則](../CLAUDE.md#yesqlの設計原則)
- [各ドライバーの実装状況](../DriverStatus.md)
- [DuckDBex公式ドキュメント](https://github.com/AlexR2D2/duckdbex)
- [元のyesqlリポジトリ](https://github.com/woylie/yesql)