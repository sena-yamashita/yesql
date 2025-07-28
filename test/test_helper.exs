# CI環境でスキップするタグを設定
if System.get_env("CI") == "true" do
  ExUnit.configure(exclude: [:skip_on_ci])
end

# 必要なアプリケーションを起動（エラーが発生しても続行）
case Application.ensure_all_started(:postgrex) do
  {:ok, _} -> :ok
  {:error, _} -> :ok
end

case Application.ensure_all_started(:ecto_sql) do
  {:ok, _} -> :ok
  {:error, _} -> :ok
end

# DuckDBテストが有効な場合のみDuckDBexを起動
if System.get_env("DUCKDB_TEST") == "true" do
  {:ok, _} = Application.ensure_all_started(:duckdbex)
else
  # DuckDBテストに関する警告を表示
  if Mix.env() == :test do
    has_duckdb_tests =
      File.ls!("test")
      |> Enum.any?(fn file ->
        file =~ ~r/duckdb.*\.exs$/ &&
          File.read!("test/#{file}") =~ ~r/@tag\s+:duckdb/
      end)

    if has_duckdb_tests do
      IO.puts("\n⚠️  DuckDBテストを実行するには: DUCKDB_TEST=true mix test")
    end
  end
end

# CI環境またはFULL_TESTが指定されている場合のみDBテストを実行
if System.get_env("CI") || System.get_env("FULL_TEST") do
  # CI環境で必要なEctoリポジトリのみを起動
  if System.get_env("CI") do
    # Ectoアプリケーションを起動
    {:ok, _} = Application.ensure_all_started(:ecto_sql)
    
    # SQLiteとDuckDBは直接接続するため、Ectoリポジトリは不要
    sqlite_test = System.get_env("SQLITE_TEST") == "true"
    duckdb_test = System.get_env("DUCKDB_TEST") == "true"
    mysql_test = System.get_env("MYSQL_TEST") == "true"
    mssql_test = System.get_env("MSSQL_TEST") == "true"
    
    # PostgreSQLリポジトリの起動（デフォルトまたは明示的に指定された場合）
    if !sqlite_test && !duckdb_test && !mysql_test && !mssql_test do
      # デフォルトはPostgreSQL
      case Yesql.TestRepo.Postgres.start_link() do
        {:ok, _} ->
          Ecto.Migrator.run(Yesql.TestRepo.Postgres, "priv/repo/migrations", :up, all: true)
          IO.puts("PostgreSQL migrations completed")
        {:error, {:already_started, _}} ->
          Ecto.Migrator.run(Yesql.TestRepo.Postgres, "priv/repo/migrations", :up, all: true)
          IO.puts("PostgreSQL migrations completed (repo already started)")
        error ->
          IO.puts("Warning: Could not start PostgreSQL TestRepo: #{inspect(error)}")
      end
    end
    
    # MySQLリポジトリの起動（MYSQL_TEST=true の場合）
    if mysql_test do
      case Yesql.TestRepo.MySQL.start_link() do
        {:ok, _} ->
          Ecto.Migrator.run(Yesql.TestRepo.MySQL, "priv/repo/migrations", :up, all: true)
          IO.puts("MySQL migrations completed")
        {:error, {:already_started, _}} ->
          Ecto.Migrator.run(Yesql.TestRepo.MySQL, "priv/repo/migrations", :up, all: true)
          IO.puts("MySQL migrations completed (repo already started)")
        error ->
          IO.puts("Warning: Could not start MySQL TestRepo: #{inspect(error)}")
      end
    end
    
    # MSSQLリポジトリの起動（MSSQL_TEST=true の場合）
    if mssql_test do
      case Yesql.TestRepo.MSSQL.start_link() do
        {:ok, _} ->
          Ecto.Migrator.run(Yesql.TestRepo.MSSQL, "priv/repo/migrations", :up, all: true)
          IO.puts("MSSQL migrations completed")
        {:error, {:already_started, _}} ->
          Ecto.Migrator.run(Yesql.TestRepo.MSSQL, "priv/repo/migrations", :up, all: true)
          IO.puts("MSSQL migrations completed (repo already started)")
        error ->
          IO.puts("Warning: Could not start MSSQL TestRepo: #{inspect(error)}")
      end
    end
  end
  
  ExUnit.start()
else
  # ローカル環境では単体テストのみ実行
  ExUnit.start(exclude: [:integration, :db_required])
  IO.puts("\n📝 ローカルモード: 単体テストのみ実行")
  IO.puts("   全テストを実行するには: FULL_TEST=true mix test\n")
end

defmodule TestHelper do
  def new_postgrex_connection(ctx) do
    # まずpostgresデータベースに接続してyesql_testデータベースを作成
    setup_opts = [
      hostname: System.get_env("POSTGRES_HOST", "localhost"),
      username: System.get_env("POSTGRES_USER", "postgres"),
      password: System.get_env("POSTGRES_PASSWORD", "postgres"),
      database: "postgres",
      port: String.to_integer(System.get_env("POSTGRES_PORT", "5432"))
    ]

    case Postgrex.start_link(setup_opts) do
      {:ok, setup_conn} ->
        # データベースが存在しない場合は作成
        Postgrex.query(setup_conn, "CREATE DATABASE yesql_test", [])
        GenServer.stop(setup_conn)

        # yesql_testデータベースに接続
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

    case Postgrex.query(ctx[:postgrex], drop_sql, []) do
      {:ok, _} -> :ok
      {:error, _} -> :ok
    end

    case Postgrex.query(ctx[:postgrex], create_sql, []) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        IO.puts("Failed to create cats table: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def truncate_postgres_cats(ctx) do
    Postgrex.query!(ctx[:postgrex], "TRUNCATE cats", [])
    :ok
  end

  def new_duckdb_connection(_ctx) do
    case System.get_env("DUCKDB_TEST") do
      "true" ->
        {:ok, db} = Duckdbex.open(":memory:")
        {:ok, conn} = Duckdbex.connection(db)
        {:ok, duckdb: conn, db: db}

      _ ->
        # 環境変数が設定されていない場合、警告メッセージを表示
        IO.puts("\n⚠️  DuckDBテストはスキップされます。実行するには: DUCKDB_TEST=true mix test")
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
  def new_mysql_connection(ctx) do
    # まずデータベースなしで接続してyesql_testデータベースを作成
    setup_opts = [
      hostname: System.get_env("MYSQL_HOST", "localhost"),
      username: System.get_env("MYSQL_USER", "root"),
      password: System.get_env("MYSQL_PASSWORD", "root"),
      port: String.to_integer(System.get_env("MYSQL_PORT", "3306"))
    ]

    case MyXQL.start_link(setup_opts) do
      {:ok, setup_conn} ->
        # データベースが存在しない場合は作成
        MyXQL.query(setup_conn, "CREATE DATABASE IF NOT EXISTS yesql_test")
        GenServer.stop(setup_conn)

        # yesql_testデータベースに接続（プロセス名を設定）
        opts = [
          hostname: System.get_env("MYSQL_HOST", "localhost"),
          username: System.get_env("MYSQL_USER", "root"),
          password: System.get_env("MYSQL_PASSWORD", "root"),
          database: System.get_env("MYSQL_DATABASE", "yesql_test"),
          port: String.to_integer(System.get_env("MYSQL_PORT", "3306")),
          name: Module.concat(ctx.module, MySQL)
        ]

        case MyXQL.start_link(opts) do
          {:ok, conn} ->
            {:ok, mysql: conn}

          {:error, _} ->
            :skip
        end

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
  def new_mssql_connection(ctx) do
    # まずmasterデータベースに接続してyesql_testデータベースを作成
    setup_opts = [
      hostname: System.get_env("MSSQL_HOST", "localhost"),
      username: System.get_env("MSSQL_USER", "sa"),
      password: System.get_env("MSSQL_PASSWORD", "YourStrong@Passw0rd"),
      database: "master",
      port: String.to_integer(System.get_env("MSSQL_PORT", "1433"))
    ]

    case Tds.start_link(setup_opts) do
      {:ok, setup_conn} ->
        # データベースが存在しない場合は作成
        Tds.query(
          setup_conn,
          """
            IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = 'yesql_test')
            CREATE DATABASE yesql_test
          """,
          []
        )

        GenServer.stop(setup_conn)

        # yesql_testデータベースに接続
        opts = [
          hostname: System.get_env("MSSQL_HOST", "localhost"),
          username: System.get_env("MSSQL_USER", "sa"),
          password: System.get_env("MSSQL_PASSWORD", "YourStrong@Passw0rd"),
          database: System.get_env("MSSQL_DATABASE", "yesql_test"),
          port: String.to_integer(System.get_env("MSSQL_PORT", "1433")),
          name: Module.concat(ctx.module, MSSQL)
        ]

        case Tds.start_link(opts) do
          {:ok, conn} ->
            {:ok, mssql: conn}

          {:error, _} ->
            :skip
        end

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

    Tds.query!(conn, drop_sql, [])
    Tds.query!(conn, create_sql, [])
    :ok
  end

  def create_mssql_test_table(_), do: :skip

  # SQLite helpers
  def new_sqlite_connection(_ctx) do
    # Exqlite.start_linkを使用してDBConnection互換の接続を作成
    opts = [
      database: ":memory:"
    ]

    case Exqlite.start_link(opts) do
      {:ok, conn} ->
        {:ok, sqlite: conn}

      {:error, _} ->
        :skip
    end
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

    {:ok, _} = Exqlite.query(conn, create_sql)
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
      Jamdb.Oracle.query(conn, "DROP TABLE users")
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

    Jamdb.Oracle.query(conn, create_sql)
    :ok
  end

  def create_oracle_test_table(_), do: :skip
end
