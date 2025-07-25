# YesSQL への貢献

YesQLへの貢献を検討していただきありがとうございます！

## 開発環境のセットアップ

### 必要な環境

- Elixir 1.14以上
- Erlang/OTP 23以上
- 各データベース（テストに必要な場合）
  - PostgreSQL
  - MySQL/MariaDB
  - DuckDB
  - SQLite
  - SQL Server
  - Oracle

### 初期セットアップ

```bash
# リポジトリをフォークしてクローン
git clone https://github.com/YOUR_USERNAME/yesql.git
cd yesql

# 依存関係をインストール
mix deps.get

# コンパイル
mix compile

# テストを実行
mix test
```

## 開発ガイドライン

### コードスタイル

- Elixirの標準的なフォーマッティングに従ってください
- `mix format`を実行してコードをフォーマット
- 関数にはドキュメントを追加してください

### LEEXトークナイザーの変更

トークナイザー（`src/Elixir.Yesql.Tokenizer.xrl`）を変更する場合：

```bash
# .erlファイルを再生成
erl -noshell -eval 'leex:file("src/Elixir.Yesql.Tokenizer.xrl"), halt().'

# 生成されたファイルをコミットに含める
git add src/Elixir.Yesql.Tokenizer.erl
```

**重要**: 生成された`.erl`ファイルは必ずコミットに含めてください。これにより、依存プロジェクトでのコンパイルが簡単になります。

### 新しいドライバーの追加

1. `lib/yesql/driver/`ディレクトリに新しいドライバーモジュールを作成
2. `Yesql.Driver`プロトコルを実装
3. `Yesql.DriverFactory`に新しいドライバーを追加
4. テストを作成（`test/`ディレクトリ）
5. ドキュメントを作成（`guides/`ディレクトリ）
6. `README.md`を更新

例：
```elixir
defmodule Yesql.Driver.NewDB do
  defstruct []
  
  defimpl Yesql.Driver, for: __MODULE__ do
    def execute(driver, conn, sql, params) do
      # 実装
    end
    
    def convert_params(driver, sql, param_spec) do
      # 実装
    end
    
    def process_result(driver, result) do
      # 実装
    end
  end
end
```

### テスト

#### 基本的なテスト

```bash
mix test
```

#### 特定のドライバーのテスト

```bash
# DuckDB
DUCKDB_TEST=true mix test test/duckdb_test.exs

# MySQL
MYSQL_TEST=true MYSQL_USER=root MYSQL_PASSWORD=password mix test test/mysql_test.exs
```

#### ストリーミングテスト

```bash
# PostgreSQL
POSTGRESQL_STREAM_TEST=true mix test test/stream_test.exs

# 全ドライバー
POSTGRESQL_STREAM_TEST=true MYSQL_STREAM_TEST=true DUCKDB_STREAM_TEST=true SQLITE_STREAM_TEST=true mix test test/stream_test.exs
```

### コミットメッセージ

セマンティックコミットメッセージを使用してください：

- `feat:` 新機能
- `fix:` バグ修正
- `docs:` ドキュメントのみの変更
- `style:` コードの意味に影響しない変更
- `refactor:` バグ修正や機能追加を伴わないコード変更
- `perf:` パフォーマンス改善
- `test:` テストの追加や修正
- `chore:` ビルドプロセスやツールの変更

例：
```
feat: Cassandraドライバーのサポートを追加

- Cassandraドライバーの実装
- パラメータ変換の実装
- 基本的なテストの追加
```

## プルリクエスト

1. 新しいブランチを作成: `git checkout -b feature/your-feature`
2. 変更をコミット: `git commit -am 'feat: 新機能の説明'`
3. ブランチをプッシュ: `git push origin feature/your-feature`
4. プルリクエストを作成

### PRチェックリスト

- [ ] テストが全て通る
- [ ] 新しい機能にはテストを追加
- [ ] ドキュメントを更新
- [ ] `mix format`を実行
- [ ] CHANGELOGを更新（必要な場合）

## 問題の報告

バグを見つけた場合や機能リクエストがある場合は、[Issues](https://github.com/sena-yamashita/yesql/issues)で報告してください。

### 良いバグレポートには以下を含めてください

- Elixir/Erlangのバージョン
- YesQLのバージョン
- 使用しているデータベースドライバー
- 再現手順
- 期待される動作
- 実際の動作
- エラーメッセージ（ある場合）

## ライセンス

貢献していただいたコードは、プロジェクトと同じApache 2.0ライセンスでリリースされます。