# Yesql

[![Version](https://img.shields.io/badge/version-3.0.0-blue.svg)](https://github.com/sena-yamashita/yesql)
[![License](https://img.shields.io/badge/license-Apache%202.0-green.svg)](LICENSE)

YesqlはSQLを_使用する_ためのElixirライブラリです。

> **注**: このリポジトリは[lpil/yesql](https://github.com/lpil/yesql)のフォークで、マルチドライバー対応を追加したものです。

## 理論的根拠

ElixirでSQLを書く必要がある場合があります。

選択肢の1つは[Ecto](https://github.com/elixir-ecto/ecto/)を使用することです。
Ectoは実行時にデータベースクエリを生成するための洗練されたDSLを提供します。
これは単純な用途には便利ですが、その抽象化は最も単純で一般的なデータベース機能でしか機能しません。
このため、抽象化が破綻して`Repo.query`や`fragment`に生のSQL文字列を渡し始めるか、
これらのデータベース機能を完全に無視することになります。

では、解決策は何でしょうか？SQLをSQLのまま保つことです。クエリを含む1つのファイルを用意します：

``` sql
SELECT *
FROM users
WHERE country_code = :country_code
```

...そして、コンパイル時にそのファイルを読み込んで通常のElixir関数に変換します：

```elixir
defmodule Query do
  use Yesql, driver: Postgrex, conn: MyApp.ConnectionPool

  Yesql.defquery("some/where/select_users_by_country.sql")
end

# `users_by_country/1`という名前の関数が作成されました。
# 使ってみましょう：
iex> Query.users_by_country(country_code: "jpn")
{:ok, [%{name: "太郎", country_code: "jpn"}]}
```

SQLとElixirを分離することで、以下の利点が得られます：

- 構文上の驚きがない。データベースはSQL標準に準拠していません - どのデータベースもそうです - 
  しかしYesqlは気にしません。「同等のEcto構文」を探す時間を無駄にすることはありません。
  `fragment("some('funky'::SYNTAX)")`関数にフォールバックする必要もありません。
- より良いエディタサポート。エディタにはおそらく優れたSQLサポートがすでにあります。
  SQLをSQLのまま保つことで、それを使用できます。
- チームの相互運用性。DBAやEctoに不慣れな開発者も、Elixirプロジェクトで使用するSQLを
  読み書きできます。
- パフォーマンスチューニングが簡単。クエリプランを`EXPLAIN`する必要がありますか？
  クエリが通常のSQLの場合、はるかに簡単です。
- クエリの再利用。同じSQLファイルを他のプロジェクトにドロップできます。
  なぜならそれらは単なるプレーンなSQLだからです。サブモジュールとして共有できます。
- シンプルさ。これは非常に小さなライブラリであり、Ectoや類似のものよりも理解しやすく、
  レビューしやすいです。


### Yesqlを使用すべきでない場合

多くの異なる種類のデータベースで同時に動作するSQLが必要な場合。
1つの複雑なクエリをMySQL、Oracle、Postgresなどの異なる方言に透過的に変換したい場合は、
SQL上の抽象化レイヤーが本当に必要です。


## 代替案

Ectoについて話しましたが、Yesqlは`$OTHER_LIBRARY`とどのように比較されますか？

### [eql](https://github.com/artemeff/eql)

eqlは同様のインスピレーションと目標を持つErlangライブラリです。

- eqlはクエリ実行のソリューションを提供しません。ライブラリユーザーが実装する必要があります。
  YesqlはフレンドリーなAPIを提供します。
- Erlangライブラリであるeqlはクエリをランタイムでコンパイルする必要がありますが、
  Yesqlはコンパイル時に行うため、初期化コードを書いたりクエリをどこかに保存したりする必要がありません。
- eqlは`neotoma` PEGコンパイラプラグインが必要ですが、YesqlはElixir標準ライブラリのみを使用します。
- Yesqlはプリペアドステートメントを使用するため、クエリパラメータはサニタイズされ、
  データベースがパラメータを受け入れる位置でのみ有効です。eqlはテンプレートツールのように機能するため、
  パラメータは任意の位置で使用でき、サニタイゼーションはユーザーに任されています。
- 主観的な点ですが、Yesqlの実装はeqlよりもシンプルでありながら、より多くの機能を提供していると思います。

### [ayesql](https://github.com/alexdesousa/ayesql)

ayesqlは別のElixirライブラリで、yesqlよりも少し強力です：

- 単一ファイル内の様々なSQL文のサポートを提供します。
- SQLファイル内での[クエリの構成可能性](https://hexdocs.pm/ayesql/readme.html#query-composition)のための特別な構成。
- SQLファイル内での[オプションパラメータ](https://hexdocs.pm/ayesql/readme.html#optional-parameters)のための特別な構成。

yesqlはSQLクエリを標準的なSQLにより近い形で保ちますが、制限や複雑さを感じ始めたら、
ayesqlやEctoのようなより強力な抽象化をチェックする良い時期かもしれません。

## サポートされているドライバー

Yesqlは複数のデータベースドライバーをサポートしています：

- **Postgrex** - PostgreSQLドライバー
- **Ecto** - 任意のEctoリポジトリで使用
- **DuckDB** - DuckDBex経由の分析データベース
- **MySQL/MariaDB** - MyXQL経由のMySQLおよびMariaDB
- **MSSQL** - Tds経由のMicrosoft SQL Server
- **Oracle** - jamdb_oracle経由のOracle Database
- **SQLite** - Exqlite経由のSQLite（v2.0で追加）

### DuckDBでの使用

```elixir
defmodule Analytics do
  use Yesql, driver: :duckdb

  # DuckDB接続を開く
  {:ok, db} = Duckdbex.open("analytics.duckdb")
  {:ok, conn} = Duckdbex.connection(db)

  # クエリを定義
  Yesql.defquery("analytics/aggregate_sales.sql")
  
  # 使用する
  Analytics.aggregate_sales(conn, start_date: "2024-01-01")
end
```

#### DuckDB詳細例：時系列分析

```sql
-- analytics/time_series_analysis.sql
-- name: time_series_analysis
WITH daily_stats AS (
  SELECT 
    DATE_TRUNC('day', created_at) as day,
    COUNT(*) as daily_count,
    SUM(amount) as daily_revenue,
    AVG(amount) as avg_order_value
  FROM orders
  WHERE created_at BETWEEN :start_date AND :end_date
    AND status = :status
  GROUP BY DATE_TRUNC('day', created_at)
),
moving_averages AS (
  SELECT 
    day,
    daily_count,
    daily_revenue,
    avg_order_value,
    AVG(daily_revenue) OVER (
      ORDER BY day 
      ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ) as revenue_7day_ma
  FROM daily_stats
)
SELECT * FROM moving_averages
ORDER BY day;
```

```elixir
# DuckDBの高度な分析機能を活用
defmodule MyApp.Analytics do
  use Yesql, driver: :duckdb
  
  # SQLファイルを読み込み
  Yesql.defquery("analytics/time_series_analysis.sql")
  
  def analyze_sales_trends(conn, date_range) do
    {:ok, results} = time_series_analysis(conn,
      start_date: date_range.start,
      end_date: date_range.end,
      status: "completed"
    )
    
    # 結果を処理してグラフ用のデータに変換
    Enum.map(results, fn row ->
      %{
        date: row.day,
        revenue: row.daily_revenue,
        trend: row.revenue_7day_ma,
        orders: row.daily_count
      }
    end)
  end
end
```

### MySQL/MariaDBでの使用

```elixir
defmodule MyApp.Queries do
  use Yesql, driver: :mysql
  
  # MySQL接続を開く
  {:ok, conn} = MyXQL.start_link(
    hostname: "localhost",
    username: "root",
    password: "password",
    database: "myapp_db"
  )
  
  # クエリを定義
  Yesql.defquery("queries/get_users.sql")
  
  # 使用する（MySQLは?形式のパラメータを使用）
  MyApp.Queries.get_users(conn, status: "active", limit: 10)
end
```

#### MySQL詳細例：全文検索とJSON操作

```sql
-- queries/search_products.sql
-- name: search_products
SELECT 
  p.id,
  p.name,
  p.description,
  p.price,
  JSON_EXTRACT(p.attributes, '$.color') as color,
  JSON_EXTRACT(p.attributes, '$.size') as size,
  MATCH(p.name, p.description) AGAINST(:search_term IN NATURAL LANGUAGE MODE) as relevance
FROM products p
WHERE 
  p.status = :status
  AND p.price BETWEEN :min_price AND :max_price
  AND (
    MATCH(p.name, p.description) AGAINST(:search_term IN NATURAL LANGUAGE MODE)
    OR p.name LIKE :search_pattern
  )
ORDER BY relevance DESC, p.created_at DESC
LIMIT :limit;
```

```elixir
# MySQLの全文検索とJSON機能を活用
defmodule MyApp.ProductSearch do
  use Yesql, driver: :mysql
  
  Yesql.defquery("queries/search_products.sql")
  
  def search(conn, term, filters \\ %{}) do
    {:ok, products} = search_products(conn,
      search_term: term,
      search_pattern: "%#{term}%",
      status: filters[:status] || "active",
      min_price: filters[:min_price] || 0,
      max_price: filters[:max_price] || 999999,
      limit: filters[:limit] || 20
    )
    
    # 結果を整形
    Enum.map(products, fn product ->
      %{
        id: product.id,
        name: product.name,
        price: Decimal.to_float(product.price),
        attributes: %{
          color: product.color,
          size: product.size
        },
        relevance_score: product.relevance
      }
    end)
  end
end
```

### MSSQL（SQL Server）での使用

```elixir
defmodule MyApp.Queries do
  use Yesql, driver: :mssql
  
  # MSSQL接続を開く
  {:ok, conn} = Tds.start_link(
    hostname: "localhost",
    username: "sa", 
    password: "YourStrong!Passw0rd",
    database: "myapp_db"
  )
  
  # クエリを定義
  Yesql.defquery("queries/reports.sql")
  
  # 使用する（MSSQLは@p1, @p2...形式のパラメータを使用）
  MyApp.Queries.monthly_report(conn, month: 12, year: 2024)
end
```

### Oracleでの使用

```elixir
defmodule MyApp.Queries do
  use Yesql, driver: :oracle
  
  # Oracle接続を開く
  {:ok, conn} = Jamdb.Oracle.start_link(
    hostname: "localhost",
    port: 1521,
    database: "XE",
    username: "myapp",
    password: "password"
  )
  
  # クエリを定義
  Yesql.defquery("queries/analytics.sql")
  
  # 使用する（Oracleは:1, :2...形式のパラメータを使用）
  MyApp.Queries.analytics_summary(conn, start_date: ~D[2024-01-01], end_date: ~D[2024-12-31])
end
```

### SQLiteでの使用

```elixir
defmodule MyApp.Queries do
  use Yesql, driver: :sqlite
  
  # SQLite接続を開く（ファイルベース）
  {:ok, conn} = Exqlite.Sqlite3.open("myapp.db")
  
  # メモリデータベースでの使用
  {:ok, mem_conn} = Exqlite.Sqlite3.open(":memory:")
  
  # クエリを定義
  Yesql.defquery("queries/local_data.sql")
  
  # 使用する（SQLiteは?形式のパラメータを使用）
  MyApp.Queries.search_local_data(conn, category: "electronics", min_price: 100)
end
```

## 新機能（v2.0）

### ストリーミング結果セット

大量のデータをメモリ効率的に処理：

```elixir
alias Yesql.Stream

# 100万件のデータをストリーミング処理
{:ok, stream} = Stream.query(conn,
  "SELECT * FROM large_table WHERE created_at > $1",
  [~D[2024-01-01]],
  driver: :postgrex,
  chunk_size: 1000
)

# ストリームを処理
count = stream
|> Stream.map(&process_row/1)
|> Stream.filter(&valid?/1)
|> Enum.count()

# ファイルへのエクスポート
{:ok, exported} = Stream.process(conn,
  "SELECT * FROM users WHERE active = true",
  [],
  fn row ->
    IO.puts(file, "#{row.id},#{row.name},#{row.email}")
  end,
  driver: :mysql,
  chunk_size: 5000
)
```

サポート状況：
- ✅ PostgreSQL（カーソルベース）
- ✅ MySQL（サーバーサイドカーソル）
- ✅ DuckDB（Arrow形式対応）
- ✅ SQLite（ステップ実行）
- ✅ MSSQL（ページネーションベース）
- ✅ Oracle（REF CURSOR/BULK COLLECT）

### バッチクエリ実行

複数のクエリを効率的に実行：

```elixir
alias Yesql.Batch

# 複数クエリの一括実行
queries = [
  {"INSERT INTO users (name, age) VALUES ($1, $2)", ["Alice", 25]},
  {"INSERT INTO users (name, age) VALUES ($1, $2)", ["Bob", 30]},
  {"UPDATE stats SET user_count = user_count + 2", []}
]

{:ok, results} = Batch.execute(queries, 
  driver: :postgrex,
  conn: conn,
  transaction: true
)

# 名前付きクエリ
named_queries = %{
  create_user: {"INSERT INTO users (name) VALUES ($1) RETURNING id", ["Charlie"]},
  create_profile: {"INSERT INTO profiles (user_id, bio) VALUES ($1, $2)", [1, "Bio"]}
}

{:ok, results} = Batch.execute_named(named_queries, driver: :postgrex, conn: conn)
user_id = results.create_user |> hd() |> Map.get(:id)
```

### 改善されたトランザクション管理

```elixir
alias Yesql.Transaction

# 分離レベルを指定
{:ok, result} = Transaction.transaction(conn, fn conn ->
  # トランザクション内での操作
  MyApp.Queries.transfer_funds(conn, from: 1, to: 2, amount: 100)
end, driver: :postgrex, isolation_level: :serializable)

# セーブポイントの使用
Transaction.transaction(conn, fn conn ->
  MyApp.Queries.insert_order(conn, order_data)
  
  Transaction.savepoint(conn, "items", driver: :postgrex)
  
  case MyApp.Queries.insert_order_items(conn, items) do
    {:error, _} ->
      Transaction.rollback_to_savepoint(conn, "items", driver: :postgrex)
      {:ok, :partial_success}
    {:ok, _} ->
      {:ok, :full_success}
  end
end, driver: :postgrex)
```

## 要件

- **Elixir**: 1.14以上
- **Erlang/OTP**: 23以上（推奨）

## インストール

### Hexパッケージとして（準備中）

```elixir
def deps do
  [
    {:yesql, "~> 2.1.0"}
  ]
end
```

### GitHubリポジトリから

```elixir
def deps do
  [
    {:yesql, git: "https://github.com/sena-yamashita/yesql.git", tag: "v2.1.0"},
    # 使用するドライバーも追加（必要なもののみ）
    {:postgrex, "~> 0.15", optional: true},
    {:myxql, "~> 0.6", optional: true},
    {:duckdbex, "~> 0.3.9", optional: true},
    # 他のドライバーも必要に応じて追加
  ]
end
```

その後、以下を実行：

```bash
mix deps.get
mix compile
```

## 開発環境のセットアップ

### リポジトリのクローンとビルド

```bash
# リポジトリをクローン
git clone https://github.com/sena-yamashita/yesql.git
cd yesql

# 依存関係の取得
mix deps.get

# LEEXファイルのコンパイル（開発時のみ必要）
# 注：生成された.erlファイルはリポジトリに含まれているため、通常は不要
erl -noshell -eval 'leex:file("src/Elixir.Yesql.Tokenizer.xrl"), halt().'

# コンパイル
mix compile
```

### 注意事項

- LEEXトークナイザー（`.xrl`ファイル）から生成される`.erl`ファイルは、依存プロジェクトでのコンパイルを簡単にするためにリポジトリに含まれています
- 開発時にトークナイザーを変更した場合は、上記のコマンドで再生成してください

## テスト

### テストモード

YesQLは2つのテストモードをサポートしています：

1. **ローカルモード（デフォルト）** - DB接続不要な単体テストのみ実行
2. **フルテストモード** - 全てのテスト（DB接続必要）を実行

### 基本的なテスト実行

```sh
# ローカルモード（単体テストのみ・高速）
mix test

# 単体テストのみを明示的に実行
mix test.unit

# フルテスト（DB接続必要）
mix test.full

# CI環境と同じ設定でテスト
mix test.ci
```

### ドライバー別テスト

各ドライバー個別のテスト実行：

```sh
# PostgreSQL用のテストデータベースを作成（初回のみ）
createdb yesql_test

# PostgreSQLテスト
mix test.postgres

# DuckDBテスト（環境変数が自動設定されます）
mix test.duckdb

# または環境変数を手動で設定
DUCKDB_TEST=true mix test --only duckdb

# MySQLテスト
mix test.mysql

# MSSQLテスト
mix test.mssql

# Oracleテスト
ORACLE_TEST=true ORACLE_PASSWORD=password mix test test/oracle_test.exs
```

### 全ドライバーの一括テスト

全てのドライバーをまとめてテストする便利なコマンド：

```sh
# 全ドライバーを順次テスト
mix test.drivers

# 特定のドライバーのみテスト
mix test.drivers postgresql duckdb

# 並列実行（高速）
mix test.drivers --parallel

# 利用可能なドライバー一覧を表示
mix test.drivers --list

# エイリアスを使用
mix test.all
```

または、スタンドアロンスクリプトとして：

```sh
# 実行権限を付与（初回のみ）
chmod +x test_all_drivers.exs

# 全ドライバーテストを実行
./test_all_drivers.exs
```

テスト結果のサマリーが表示され、各ドライバーの成功/失敗状態が一目で確認できます。

### 環境変数について

テスト実行時、特定のドライバーのテストは環境変数の設定が必要です。
環境変数が設定されていない場合、該当するテストはスキップされ、警告メッセージが表示されます：

```
⚠️  DuckDBテストを実行するには: DUCKDB_TEST=true mix test
```

この仕組みにより、必要な環境変数の設定を忘れることを防ぎます。

**主な環境変数:**
- `DUCKDB_TEST=true` - DuckDBテストを有効化
- `MYSQL_TEST=true` - MySQLテストを有効化
- `MSSQL_TEST=true` - MSSQLテストを有効化
- `ORACLE_TEST=true` - Oracleテストを有効化
- `FULL_TEST=true` - 全ての統合テストを実行
- `CI=true` - CI環境での実行（全テスト実行）

### パフォーマンステスト

YesQLの抽象化レイヤーのオーバーヘッドを測定できます：

```sh
# ベンチマークの実行
cd bench
./run_benchmarks.sh all

# 特定のドライバーのみ
./run_benchmarks.sh postgresql
./run_benchmarks.sh mysql
```


## 他の言語

Yesqlは[Kris JenkinsのClojure Yesql](https://github.com/krisajenkins/yesql)に~~パクり~~インスパイアされています。
多くの言語で同様のライブラリが見つかります：

| 言語       | プロジェクト                                        |
| ---        | ---                                                |
| C#         | [JaSql](https://bitbucket.org/rick/jasql)          |
| Clojure    | [YeSPARQL](https://github.com/joelkuiper/yesparql) |
| Clojure    | [Yesql](https://github.com/krisajenkins/yesql)     |
| Elixir     | [ayesql](https://github.com/alexdesousa/ayesql)    |
| Erlang     | [eql](https://github.com/artemeff/eql)             |
| Go         | [DotSql](https://github.com/gchaincl/dotsql)       |
| Go         | [goyesql](https://github.com/nleof/goyesql)        |
| JavaScript | [Preql](https://github.com/NGPVAN/preql)           |
| JavaScript | [sqlt](https://github.com/eugeneware/sqlt)         |
| PHP        | [YepSQL](https://github.com/LionsHead/YepSQL)      |
| Python     | [Anosql](https://github.com/honza/anosql)          |
| Ruby       | [yayql](https://github.com/gnarmis/yayql)          |


## このフォークについて

このリポジトリは、オリジナルの[lpil/yesql](https://github.com/lpil/yesql) v1.0.1からフォークし、マルチドライバー対応を追加したものです。

### v2.0.0での追加機能

- **マルチドライバー対応**: ドライバー抽象化レイヤーの実装により、新しいデータベースドライバーの追加が容易になりました
- **DuckDBサポート**: [DuckDBex](https://github.com/AlexR2D2/duckdbex)を使用したDuckDBドライバーの実装
- **MySQL/MariaDBサポート**: [MyXQL](https://github.com/elixir-ecto/myxql)を使用したMySQLドライバーの実装
- **MSSQLサポート**: [Tds](https://github.com/livehelpnow/tds)を使用したSQL Serverドライバーの実装
- **Oracleサポート**: [jamdb_oracle](https://github.com/erlangbureau/jamdb_oracle)を使用したOracleドライバーの実装
- **日本語ドキュメント**: 全てのドキュメントを日本語化
- **Elixir 1.14互換性**: 最小Elixirバージョンを1.14に更新

### 開発について

このマルチドライバー対応の実装は、[Claude Code](https://claude.ai/code)を使用して開発されました。
Claude Codeは、AIペアプログラミングツールとして、以下の作業を支援しました：

- アーキテクチャ設計と実装
- ドライバー抽象化レイヤーの構築
- テストスイートの作成
- ドキュメントの作成と翻訳

詳細な実装履歴は、コミットログを参照してください。各コミットメッセージには `🤖 Generated with Claude Code` が含まれています。

### 変更履歴

詳細な変更内容については[CHANGELOG.md](CHANGELOG.md)を参照してください。

## オリジナルライセンス

Copyright © 2018 Louis Pilfold. All Rights Reserved.

## フォーク版の追加実装

マルチドライバー対応の実装:
- Copyright © 2024 Daisuke Yamashita
- Copyright © 2024 SENA Networks, Inc.

このフォーク版も、オリジナルと同じApache 2.0ライセンスの下で公開されています。

### 貢献者

- **Daisuke Yamashita** (SENA Networks, Inc.) - マルチドライバー対応の設計と実装
- **Claude Code** (Anthropic) - AIペアプログラミングツールとしての開発支援