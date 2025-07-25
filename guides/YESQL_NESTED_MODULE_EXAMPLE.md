# YesQL ネストされたモジュールでの使用方法

## 問題

ネストされたモジュール内で`Yesql.defquery`を使用する場合、親モジュールの`use Yesql`設定は自動的に継承されません。

## 解決方法

### 方法1: ネストされたモジュールでも`use Yesql`を使用

```elixir
defmodule Mix.Tasks.SkyseaDuckdbEtl do
  use Mix.Task
  use Timex

  defmodule Query do
    use Yesql, driver: :duckdb  # ここでも use Yesql を指定
    
    # クエリを定義
    Yesql.defquery("sql/skysea/import_csv.sql")
  end

  @shortdoc "SKYSEA LOG ETL: `mix skysea_log_etl`"

  def run(_) do
    Mix.Task.run("app.start", [])
    
    {:ok, db} = Duckdbex.open("./skysea.db")
    {:ok, conn} = Duckdbex.connection(db)

    {:ok, result} = Query.import_csv(conn)

    IO.inspect(result)
  end
end
```

### 方法2: defqueryで直接ドライバーを指定

```elixir
defmodule Mix.Tasks.SkyseaDuckdbEtl do
  use Mix.Task
  use Timex

  defmodule Query do
    use Yesql  # driver指定なし
    
    # クエリごとにドライバーを指定
    Yesql.defquery("sql/skysea/import_csv.sql", driver: :duckdb)
  end

  # ... rest of the code
end
```

### 方法3: 親モジュールでクエリを定義（推奨）

```elixir
defmodule Mix.Tasks.SkyseaDuckdbEtl do
  use Mix.Task
  use Timex
  use Yesql, driver: :duckdb

  # 親モジュールで直接クエリを定義
  Yesql.defquery("sql/skysea/import_csv.sql")

  @shortdoc "SKYSEA LOG ETL: `mix skysea_log_etl`"

  def run(_) do
    Mix.Task.run("app.start", [])
    
    {:ok, db} = Duckdbex.open("./skysea.db")
    {:ok, conn} = Duckdbex.connection(db)

    # 親モジュールの関数として呼び出し
    {:ok, result} = import_csv(conn)

    IO.inspect(result)
  end
end
```

### 方法4: 専用のクエリモジュールを作成

```elixir
# lib/skysea/queries.ex
defmodule Skysea.Queries do
  use Yesql, driver: :duckdb
  
  Yesql.defquery("sql/skysea/import_csv.sql")
  # 他のクエリもここに追加
end

# lib/mix/tasks/skysea_duckdb_etl.ex
defmodule Mix.Tasks.SkyseaDuckdbEtl do
  use Mix.Task
  use Timex
  
  alias Skysea.Queries

  @shortdoc "SKYSEA LOG ETL: `mix skysea_log_etl`"

  def run(_) do
    Mix.Task.run("app.start", [])
    
    {:ok, db} = Duckdbex.open("./skysea.db")
    {:ok, conn} = Duckdbex.connection(db)

    {:ok, result} = Queries.import_csv(conn)

    IO.inspect(result)
  end
end
```

## なぜこの問題が発生するか

`use Yesql`マクロは、現在のモジュールのコンテキストでモジュール属性（`@yesql_private__driver`）を設定します。ネストされたモジュールは独立したコンテキストを持つため、親モジュールの属性を継承しません。

## 推奨事項

1. **Mix タスクの場合**: 方法3（親モジュールで直接定義）が最もシンプル
2. **複数のクエリがある場合**: 方法4（専用モジュール）が保守性が高い
3. **一時的な使用**: 方法2（defqueryでドライバー指定）が柔軟