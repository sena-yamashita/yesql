# Ectoを使用したテスト環境セットアップ

## 概要

YesQLのテスト環境では、各データベースドライバーの直接的なテストを維持しながら、
データベースの初期セットアップとマイグレーションはEctoで統一しています。

## 背景

- 各データベース（PostgreSQL、MySQL、MSSQL）のセットアップに苦労していた
- データベースごとに異なるセットアップコードを維持する必要があった
- CI環境でのテスト失敗の原因調査が困難だった

## 解決策

既存のEctoドライバーサポートを活用して、テスト環境のセットアップを簡略化：

1. **Ectoアダプターの活用**
   - `Ecto.Adapters.Postgres` (Postgrex)
   - `Ecto.Adapters.MyXQL` (MySQL)
   - `Ecto.Adapters.Tds` (MSSQL)

2. **統一的なセットアップ**
   - データベース作成
   - テーブル作成
   - 初期データ投入

## 実装

### テストヘルパー

```elixir
# test/support/ecto_test_helper.ex
defmodule Yesql.EctoTestHelper do
  def ensure_database_exists(db_type) do
    # 各データベースのyesql_testデータベースを作成
  end

  def create_test_tables(conn, db_type) do
    # 既存のテストが期待するテーブル構造を維持
  end
end
```

### 環境変数による制御

```bash
# Ectoセットアップを有効化
export SETUP_DB_WITH_ECTO=true
```

### Docker環境での使用

```bash
# Ectoセットアップ付きでテスト実行
./docker/run-tests-with-ecto.sh all
```

## 利点

1. **簡潔性**: データベースセットアップコードの統一
2. **保守性**: Ectoの成熟したAPIを活用
3. **拡張性**: 新しいデータベースの追加が容易
4. **互換性**: 既存のテストコードは変更不要

## 注意事項

- SQLiteはEctoアダプターがないため、直接ドライバーを使用
- DuckDBも同様に直接ドライバーを使用
- Oracleサポートは将来的に検討

## 今後の展望

1. CI環境でのEctoセットアップの活用
2. マイグレーション管理の統一
3. テストデータのシード機能の拡充