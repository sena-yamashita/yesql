# Yesql

YesqlはSQLを_使用する_ためのElixirライブラリです。

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

## 開発とテスト

```sh
createdb yesql_test
mix deps.get
mix test
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


## ライセンス

Copyright © 2018 Louis Pilfold. All Rights Reserved.