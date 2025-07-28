# CI調査レポート v8 - 2025-07-28

## 概要
前回の修正（CI環境でトランザクションを無効化）後も、BatchTestの失敗が継続。さらにフォーマットエラーも発生。

## 検出された問題

### 1. BatchTestの失敗（継続）
**状況**: トランザクション無効化の対応後も同じエラーが発生
**エラー詳細**:
```
test/batch_test.exs:135
Assertion with == failed
code:  assert results.count_all == [%{count: 2}]
left:  [%{count: 0}]
right: [%{count: 2}]
```

**考えられる原因**:
- トランザクション設定が正しく適用されていない
- バッチ処理自体に問題がある
- CI環境でのデータベース接続の問題

### 2. フォーマットエラー（新規）
**状況**: batch_test.exsのフォーマットエラー
**原因**: 前回の修正でフォーマットを実行し忘れた

## 実施した対応

### 今回の対応
1. **デバッグ出力を追加**
   - CI環境でのトランザクション設定値を出力
   - バッチ実行結果を詳細に出力
   - 直接クエリでのカウント結果を確認

2. **フォーマット修正**
   - `mix format`を実行

### コード変更
```elixir
# デバッグ用出力
if System.get_env("CI") do
  IO.puts("CI環境でのBatchTest実行: transaction = #{transaction_opt}")
  IO.inspect(results, label: "CI環境でのBatch実行結果")
  
  # 直接カウントを確認
  {:ok, direct_count} = Postgrex.query(conn, "SELECT COUNT(*) as count FROM batch_test", [])
  IO.inspect(direct_count.rows, label: "直接クエリでのカウント")
end
```

## 推測される根本原因

1. **バッチ処理の実装問題**
   - `Yesql.Batch.execute_named`がCI環境で正しく動作しない
   - クエリの実行順序の問題

2. **環境変数の確認**
   - `System.get_env("CI")`が期待通りの値を返しているか

3. **データベース接続の問題**
   - CI環境での接続プーリング
   - 複数のクエリを同時実行する際の問題

## 次のステップ

1. デバッグ出力を確認してトランザクション設定が正しく適用されているか確認
2. バッチ実行結果の詳細を分析
3. 必要に応じて、CI環境でこのテストをスキップすることを再検討

## ローカルCI環境の構築

ユーザーからの提案に基づき、ローカルでCI環境を再現するためのセットアップを実施：

1. **actツールを使用したローカルCI環境**
   - `docs/development/local_ci_setup.md`を作成
   - `scripts/setup-local-ci.sh`でセットアップを自動化
   - `scripts/debug-batch-test.sh`でBatchTestをローカルデバッグ
   - `scripts/run-local-ci.sh`でactを簡単に実行

2. **BatchTestデバッグワークフロー**
   - `.github/workflows/batch-test-debug.yml`を作成
   - 個別のINSERTテストを含む詳細なデバッグ
   - Batch.execute_namedの実装確認ステップ

3. **テストコードの改善**
   - より詳細なデバッグ出力を追加
   - 個別クエリ実行とバッチ実行の比較
   - トランザクション状態の可視化

## 推測される問題

1. **execute_named関数の実装**
   - Map.keys()の順序が保証されない可能性
   - トランザクション内でのクエリ実行順序

2. **CI環境固有の問題**
   - PostgreSQLの接続プーリング設定
   - トランザクション分離レベル
   - 自動コミットモードの違い

## 結論

トランザクション無効化の対応だけでは問題が解決しなかった。ローカルCI環境を構築し、効率的にデバッグできる環境を整備した。これにより、GitHub上でのデバッグサイクルを大幅に短縮できる。