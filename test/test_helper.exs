{:ok, _} = Application.ensure_all_started(:postgrex)

# DuckDBテストが有効な場合のみDuckDBexを起動
if System.get_env("DUCKDB_TEST") == "true" do
  {:ok, _} = Application.ensure_all_started(:duckdbex)
end

ExUnit.start()

defmodule TestHelper do
  def check_postgres_connection() do
    opts = [
      hostname: System.get_env("POSTGRES_HOST", "localhost"),
      username: System.get_env("POSTGRES_USER", "postgres"), 
      password: System.get_env("POSTGRES_PASSWORD", "postgres"),
      database: System.get_env("POSTGRES_DATABASE", "yesql_test"),
      port: String.to_integer(System.get_env("POSTGRES_PORT", "5432"))
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
      hostname: System.get_env("POSTGRES_HOST", "localhost"),
      username: System.get_env("POSTGRES_USER", "postgres"),
      password: System.get_env("POSTGRES_PASSWORD", "postgres"),
      database: System.get_env("POSTGRES_DATABASE", "yesql_test"),
      port: String.to_integer(System.get_env("POSTGRES_PORT", "5432")),
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

  # MySQL helpers
  def new_mysql_connection(_ctx) do
    opts = [
      hostname: System.get_env("MYSQL_HOST", "localhost"),
      username: System.get_env("MYSQL_USER", "root"),
      password: System.get_env("MYSQL_PASSWORD", "root"),
      database: System.get_env("MYSQL_DATABASE", "yesql_test"),
      port: String.to_integer(System.get_env("MYSQL_PORT", "3306"))
    ]

    case MyXQL.start_link(opts) do
      {:ok, conn} -> 
        {:ok, mysql: conn}
      {:error, _} ->
        :skip
    end
  end

  def create_mysql_test_table(%{mysql: conn}) do
    drop_sql = "DROP TABLE IF EXISTS users"
    create_sql = """
    CREATE TABLE users (
      id INT AUTO_INCREMENT PRIMARY KEY,
      name VARCHAR(255),
      age INT,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )
    """
    
    MyXQL.query!(conn, drop_sql)
    MyXQL.query!(conn, create_sql)
    :ok
  end
  def create_mysql_test_table(_), do: :skip

  # MSSQL helpers
  def new_mssql_connection(_ctx) do
    opts = [
      hostname: System.get_env("MSSQL_HOST", "localhost"),
      username: System.get_env("MSSQL_USER", "sa"),
      password: System.get_env("MSSQL_PASSWORD", "YourStrong!Passw0rd"),
      database: System.get_env("MSSQL_DATABASE", "yesql_test"),
      port: String.to_integer(System.get_env("MSSQL_PORT", "1433"))
    ]

    case Tds.start_link(opts) do
      {:ok, conn} -> 
        {:ok, mssql: conn}
      {:error, _} ->
        :skip
    end
  end

  def create_mssql_test_table(%{mssql: conn}) do
    drop_sql = "IF OBJECT_ID('users', 'U') IS NOT NULL DROP TABLE users"
    create_sql = """
    CREATE TABLE users (
      id INT IDENTITY(1,1) PRIMARY KEY,
      name NVARCHAR(255),
      age INT,
      created_at DATETIME DEFAULT GETDATE()
    )
    """
    
    Tds.query!(conn, drop_sql)
    Tds.query!(conn, create_sql)
    :ok
  end
  def create_mssql_test_table(_), do: :skip

  # SQLite helpers
  def new_sqlite_connection(_ctx) do
    {:ok, conn} = Exqlite.Sqlite3.open(":memory:")
    {:ok, sqlite: conn}
  end

  def create_sqlite_test_table(%{sqlite: conn}) do
    create_sql = """
    CREATE TABLE IF NOT EXISTS users (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT,
      age INTEGER,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )
    """
    
    Exqlite.Sqlite3.execute(conn, create_sql)
    :ok
  end
  def create_sqlite_test_table(_), do: :skip

  # Oracle helpers
  def new_oracle_connection(_ctx) do
    opts = [
      hostname: System.get_env("ORACLE_HOST", "localhost"),
      port: String.to_integer(System.get_env("ORACLE_PORT", "1521")),
      database: System.get_env("ORACLE_DATABASE", "XE"),
      username: System.get_env("ORACLE_USER", "yesql_test"),
      password: System.get_env("ORACLE_PASSWORD", "yesql_test")
    ]

    case Jamdb.Oracle.start_link(opts) do
      {:ok, conn} -> 
        {:ok, oracle: conn}
      {:error, _} ->
        :skip
    end
  end

  def create_oracle_test_table(%{oracle: conn}) do
    # Oracle doesn't support IF EXISTS, so we catch the error
    try do
      Jamdb.Oracle.query!(conn, "DROP TABLE users")
    rescue
      _ -> :ok
    end

    create_sql = """
    CREATE TABLE users (
      id NUMBER GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
      name VARCHAR2(255),
      age NUMBER,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )
    """
    
    Jamdb.Oracle.query!(conn, create_sql)
    :ok
  end
  def create_oracle_test_table(_), do: :skip
end
