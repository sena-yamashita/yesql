# CI調査レポート v3 - 2025-07-28

## 問題の概要

ローカルでの`make test-all`は成功するが、GitHub CI環境では以下のエラーが発生：

1. **PostgreSQL**: `missing the :database key in options`
2. **MSSQL**: `Cannot open database "yesql_test"`
3. **その他**: 各データベースへの接続エラー

## エラーの詳細

### 1. PostgreSQLエラー
```
08:16:48.832 [error] Postgrex.Protocol (#PID<0.3351.0>) failed to connect: ** (ArgumentError) missing the :database key in options for Yesql.TestRepo.Postgres
```

### 2. MSSQLエラー
```
08:35:44.215 [error] Tds.Protocol (#PID<0.3359.0>) failed to connect: ** (Tds.Error) Line 1 (Error 4063): Cannot open database "yesql_test" that was requested by the login. Using the user default database "master" instead.
```

## ローカルとCI環境の違い

### ローカル環境（make test-all成功）
1. Dockerコンテナが起動
2. `docker/run-tests.sh`がデータベースを作成
3. 各テストが環境変数で制御され、適切なリポジトリのみ起動

### CI環境（失敗）
1. GitHub Actionsのサービスコンテナを使用
2. データベース作成が行われていない可能性
3. 設定ファイルの読み込み順序の問題

## 原因分析

### 1. データベース作成タイミング
- CI環境では、テスト実行前にデータベースが作成されていない
- `.github/workflows/elixir.yml`でデータベース作成処理が不足

### 2. 設定ファイルの問題
- `config/config.exs`で`import_config "test.exs"`を使用
- CI環境でのコンパイル時に設定が正しく反映されない可能性

### 3. 環境変数の不一致
- ローカル: `docker/run-tests.sh`で環境変数を設定
- CI: GitHub Actionsのenv設定と異なる可能性

## 解決策の検討

### 1. CI環境でのデータベース作成
`.github/workflows/elixir.yml`に明示的なデータベース作成ステップを追加

### 2. 設定ファイルの改善
- `config/test.exs`の設定を確実に読み込む
- 環境変数のデフォルト値を適切に設定

### 3. テストヘルパーの改善
`test_helper.exs`でCI環境を検出し、適切な処理を行う

## 修正内容

### 1. GitHub Actionsファイルの修正

#### `.github/workflows/database-tests.yml`
- `CI: true`環境変数を全体と各ジョブに追加
- PostgreSQLテストに`FULL_TEST: true`を追加
- MSSQLテストにデータベース作成処理を追加
- `MSSQL_DATABASE`を`master`から`yesql_test`に変更

#### `.github/workflows/elixir.yml`
- `CI: true`と`FULL_TEST: true`をテスト実行時に追加

#### `.github/workflows/ci.yml`
- グローバルに`CI: true`を追加
- `MSSQL_DATABASE`を`master`から`yesql_test`に変更

### 2. 修正の理由

#### CI環境変数
`test_helper.exs`でCI環境を検出して適切な処理を行うため、`CI=true`が必須。

#### FULL_TEST環境変数
`test_helper.exs`でEctoリポジトリを起動する条件として使用。

#### データベース作成
GitHub Actionsのサービスコンテナでは、データベースが自動作成されない場合があるため、明示的に作成。

## デグレード防止策

1. **環境変数の統一**
   - ローカルとCIで同じ環境変数を使用
   - 条件分岐が一致するよう確認

2. **テストの互換性**
   - 既存のテストコードは変更しない
   - CI環境固有の処理は環境変数で制御

3. **設定ファイルの整合性**
   - `config/config.exs`が`config/test.exs`を正しくインポート
   - 各データベースの設定が一致

## 残りの作業

1. 変更をコミット・プッシュ
2. CI結果を確認
3. 必要に応じて追加修正