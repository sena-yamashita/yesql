# CI調査レポート v4 - 2025-07-28

## 問題の概要

前回の修正後も、GitHub CIで以下のエラーが継続：

1. **MSSQL**: データベース作成コマンドが証明書エラーで失敗
2. **その他**: 環境変数の設定にもかかわらず、一部のジョブで問題が継続

## 詳細な問題分析

### 1. MSSQLデータベース作成の失敗

**エラー**
```
Sqlcmd: Error: Microsoft ODBC Driver 18 for SQL Server : SSL Provider: [error:0A000086:SSL routines::certificate verify failed:self-signed certificate]
```

**原因**
- `mssql-tools18`はデフォルトでSSL証明書の検証を要求
- GitHub ActionsのMSSQLサービスコンテナは自己署名証明書を使用
- 現在のコマンドに`-C`オプション（証明書検証スキップ）が不足

**現在のコマンド**
```bash
/opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'YourStrong@Passw0rd' -Q "CREATE DATABASE yesql_test" || true
```

**必要な修正**
```bash
/opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'YourStrong@Passw0rd' -Q "CREATE DATABASE yesql_test" -C || true
```

### 2. PostgreSQLでの問題

Elixir CIジョブでは、環境変数が正しく設定されているため、PostgreSQLテストは正常に動作している模様。

### 3. 環境の違い

**ローカル（make test-all）**
- Dockerコンテナを使用
- `docker/run-tests.sh`でデータベースを作成
- 証明書の問題なし

**GitHub Actions**
- サービスコンテナを使用
- 自己署名証明書によるSSL接続
- `mssql-tools18`の仕様変更への対応が必要

## 修正内容

### 1. `.github/workflows/database-tests.yml`

MSSQLデータベース作成コマンドに`-C`オプションを追加：

```yaml
- name: Wait for MSSQL
  run: |
    sudo apt-get update && sudo apt-get install -y mssql-tools18
    for i in {1..30}; do
      /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'YourStrong@Passw0rd' -Q 'SELECT 1' -b -No -C && break
      echo "Waiting for MSSQL to be ready..."
      sleep 2
    done
    # Create yesql_test database
    /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'YourStrong@Passw0rd' -Q "CREATE DATABASE yesql_test" -C || true
```

### 2. その他のワークフローファイル

同様の問題がある可能性があるため、すべてのMSSQL関連のコマンドを確認し、`-C`オプションを追加。

## デグレード防止策

1. **既存機能への影響なし**
   - `-C`オプションは証明書検証をスキップするだけ
   - テスト環境のみの変更

2. **ローカル環境との互換性**
   - ローカルのDockerテストには影響なし
   - `docker/run-tests.sh`は変更不要

3. **セキュリティ**
   - テスト環境のみの設定
   - 本番環境には影響なし

## 今後の改善提案

1. **環境変数による制御**
   - `MSSQL_TRUST_SERVER_CERTIFICATE`環境変数の追加検討
   - より柔軟な設定管理

2. **エラーハンドリングの改善**
   - データベース作成の成功確認
   - より詳細なログ出力

3. **ドキュメントの充実**
   - CI環境のセットアップ手順
   - トラブルシューティングガイドの拡充