{:ok, _} = Application.ensure_all_started(:postgrex)

# DuckDBテストが有効な場合のみDuckDBexを起動
if System.get_env("DUCKDB_TEST") == "true" do
  {:ok, _} = Application.ensure_all_started(:duckdbex)
end

ExUnit.start()

defmodule TestHelper do
  def check_postgres_connection() do
    opts = [
      hostname: "localhost",
      username: "postgres", 
      password: "postgres",
      database: "yesql_test"
    ]
    
    case Postgrex.start_link(opts) do
      {:ok, conn} ->
        Process.exit(conn, :normal)
        {:ok, :connected}
      {:error, _} ->
        {:error, :connection_failed}
    end
  end
  def new_postgrex_connection(ctx) do
    opts = [
      hostname: "localhost",
      username: "postgres",
      password: "postgres",
      database: "yesql_test",
      name: Module.concat(ctx.module, Postgrex)
    ]

    case Postgrex.start_link(opts) do
      {:ok, conn} -> 
        {:ok, postgrex: conn}
      {:error, _} ->
        {:error, :connection_failed}
    end
  end

  def create_cats_postgres_table(ctx) do
    drop_sql = """
    DROP TABLE IF EXISTS cats;
    """

    create_sql = """
    CREATE TABLE cats (
      age  integer NOT NULL,
      name varchar
    );
    """

    Postgrex.query!(ctx.postgrex, drop_sql, [])
    Postgrex.query!(ctx.postgrex, create_sql, [])
    :ok
  end

  def truncate_postgres_cats(ctx) do
    Postgrex.query!(ctx.postgrex, "TRUNCATE cats", [])
    :ok
  end

  def new_duckdb_connection(_ctx) do
    case System.get_env("DUCKDB_TEST") do
      "true" ->
        {:ok, db} = Duckdbex.open(":memory:")
        {:ok, conn} = Duckdbex.connection(db)
        {:ok, duckdb: conn, db: db}
      _ ->
        :skip
    end
  end

  def create_ducks_duckdb_table(%{duckdb: conn}) do
    drop_sql = """
    DROP TABLE IF EXISTS ducks;
    """

    create_sql = """
    CREATE TABLE ducks (
      age  INTEGER NOT NULL,
      name VARCHAR
    );
    """

    Duckdbex.query(conn, drop_sql, [])
    Duckdbex.query(conn, create_sql, [])
    :ok
  end
  def create_ducks_duckdb_table(_), do: :skip

  def truncate_duckdb_ducks(%{duckdb: conn}) do
    Duckdbex.query(conn, "DELETE FROM ducks", [])
    :ok
  end
  def truncate_duckdb_ducks(_), do: :skip
end
