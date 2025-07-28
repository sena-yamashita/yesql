# CI調査レポート v5 - 2025-07-28

## 概要
trust_server_certificate設定追加後のCI実行で新たなエラーが発生。

## 検出された問題

### 1. コードフォーマットエラー
**状況**: CIのFormat Checkジョブが失敗
**原因**: 
- config/test.exsとtest/test_helper.exsの空白やインデントが不正
- Elixirのコードフォーマッタ規約に違反

**対応**: 
- `mix format`を実行して修正済み

### 2. MSSQLデータベース接続エラー
**状況**: CI環境でMSSQLテストが失敗
**エラーメッセージ**:
```
Tds.Protocol failed to connect: ** (Tds.Error) Line 1 (Error 4063): 
Cannot open database "yesql_test" that was requested by the login. 
Using the user default database "master" instead.
```

**原因**:
1. ci.ymlワークフローにMSSQLデータベース作成ステップが欠如
2. パスワードの不一致:
   - ci.yml: `YourStrong@Passw0rd`
   - elixir.yml: `YourStrong!Passw0rd`
   - test環境設定: `YourStrong@Passw0rd`

**必要な対応**:
- ci.ymlにMSSQLデータベース作成ステップを追加
- パスワードを統一（`YourStrong@Passw0rd`に）

### 3. DuckDBパラメータエラー
**状況**: DuckDBテストでパラメータ関連のエラー
**エラーメッセージ**:
```
Invalid Input Error: Values were not provided for the following prepared statement parameters: 1
```

**原因**: 調査中（trust_server_certificate設定とは無関係）

## 実施した対応

### 1. フォーマット修正
```bash
mix format
```

### 2. trust_server_certificate設定の追加（完了済み）
以下のファイルに設定を追加:
- config/test.exs: Yesql.TestRepo.MSSQL設定
- test/test_helper.exs: new_mssql_connection関数の両接続設定

## 次のステップ

### 優先度: 高
1. ci.ymlにMSSQLデータベース作成ステップを追加
2. elixir.ymlのMSSQLパスワードを修正（YourStrong!Passw0rd → YourStrong@Passw0rd）
3. フォーマット修正をコミット

### 優先度: 中
1. DuckDBパラメータエラーの調査と修正

## デグレード防止策

1. **ローカルテスト**: `make test-all`が引き続き動作することを確認
2. **CI設定の統一**: すべてのワークフローで同じデータベース設定を使用
3. **フォーマットチェック**: コミット前に`mix format --check-formatted`を実行

## 注意事項

- trust_server_certificate設定自体は正しく実装されている
- MSSQLデータベースが作成されれば、接続は成功するはず
- DuckDBエラーは別の問題であり、個別に対応が必要