defmodule Yesql.EctoTestHelper do
  @moduledoc """
  Ectoを使用したテストヘルパー

  既存のテストを大きく変更せずに、
  データベースセットアップのみEctoで統一する
  """

  def ensure_database_exists(db_type) do
    case db_type do
      "postgres" ->
        ensure_postgres_database()

      "mysql" ->
        ensure_mysql_database()

      "mssql" ->
        ensure_mssql_database()

      _ ->
        {:error, :unsupported_database}
    end
  end

  defp ensure_postgres_database do
    # postgresデータベースに接続
    opts = [
      hostname: System.get_env("POSTGRES_HOST", "localhost"),
      username: System.get_env("POSTGRES_USER", "postgres"),
      password: System.get_env("POSTGRES_PASSWORD", "postgres"),
      database: "postgres",
      port: String.to_integer(System.get_env("POSTGRES_PORT", "5432"))
    ]

    case Postgrex.start_link(opts) do
      {:ok, conn} ->
        # yesql_testデータベースを作成（存在しない場合）
        case Postgrex.query(conn, "CREATE DATABASE yesql_test", []) do
          {:ok, _} ->
            IO.puts("Created PostgreSQL database: yesql_test")

          {:error, %{postgres: %{code: :duplicate_database}}} ->
            IO.puts("PostgreSQL database already exists: yesql_test")

          error ->
            IO.puts("PostgreSQL database creation error: #{inspect(error)}")
        end

        GenServer.stop(conn)
        :ok

      {:error, reason} ->
        IO.puts("Failed to connect to PostgreSQL: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp ensure_mysql_database do
    opts = [
      hostname: System.get_env("MYSQL_HOST", "localhost"),
      username: System.get_env("MYSQL_USER", "root"),
      password: System.get_env("MYSQL_PASSWORD", "root"),
      port: String.to_integer(System.get_env("MYSQL_PORT", "3306"))
    ]

    case MyXQL.start_link(opts) do
      {:ok, conn} ->
        {:ok, _} = MyXQL.query(conn, "CREATE DATABASE IF NOT EXISTS yesql_test")
        IO.puts("Ensured MySQL database exists: yesql_test")
        GenServer.stop(conn)
        :ok

      {:error, reason} ->
        IO.puts("Failed to connect to MySQL: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp ensure_mssql_database do
    opts = [
      hostname: System.get_env("MSSQL_HOST", "localhost"),
      username: System.get_env("MSSQL_USER", "sa"),
      password: System.get_env("MSSQL_PASSWORD", "YourStrong@Passw0rd"),
      database: "master",
      port: String.to_integer(System.get_env("MSSQL_PORT", "1433"))
    ]

    case Tds.start_link(opts) do
      {:ok, conn} ->
        {:ok, _} =
          Tds.query(
            conn,
            """
              IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = 'yesql_test')
              CREATE DATABASE yesql_test
            """,
            []
          )

        IO.puts("Ensured MSSQL database exists: yesql_test")
        GenServer.stop(conn)
        :ok

      {:error, reason} ->
        IO.puts("Failed to connect to MSSQL: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  各データベース用の基本テーブルを作成
  既存のテストが期待するテーブル構造を維持
  """
  def create_test_tables(conn, db_type) do
    case db_type do
      :postgrex -> create_postgres_tables(conn)
      :mysql -> create_mysql_tables(conn)
      :mssql -> create_mssql_tables(conn)
      :duckdb -> create_duckdb_tables(conn)
      :sqlite -> create_sqlite_tables(conn)
      _ -> {:error, :unsupported_database}
    end
  end

  defp create_postgres_tables(conn) do
    # cats テーブル（既存のテストが期待する構造）
    Postgrex.query!(conn, "DROP TABLE IF EXISTS cats CASCADE", [])

    Postgrex.query!(
      conn,
      """
        CREATE TABLE cats (
          age  INTEGER NOT NULL,
          name VARCHAR
        )
      """,
      []
    )

    # users テーブル
    Postgrex.query!(conn, "DROP TABLE IF EXISTS users CASCADE", [])

    Postgrex.query!(
      conn,
      """
        CREATE TABLE users (
          id SERIAL PRIMARY KEY,
          name VARCHAR(255) NOT NULL,
          age INTEGER NOT NULL,
          email VARCHAR(255)
        )
      """,
      []
    )

    :ok
  end

  defp create_mysql_tables(conn) do
    MyXQL.query!(conn, "DROP TABLE IF EXISTS users", [])

    MyXQL.query!(
      conn,
      """
        CREATE TABLE users (
          id INT AUTO_INCREMENT PRIMARY KEY,
          name VARCHAR(255) NOT NULL,
          age INT NOT NULL,
          email VARCHAR(255),
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
      """,
      []
    )

    :ok
  end

  defp create_mssql_tables(conn) do
    Tds.query!(conn, "IF OBJECT_ID('users', 'U') IS NOT NULL DROP TABLE users", [])

    Tds.query!(
      conn,
      """
        CREATE TABLE users (
          id INT IDENTITY(1,1) PRIMARY KEY,
          name NVARCHAR(255) NOT NULL,
          age INT NOT NULL,
          email NVARCHAR(255),
          created_at DATETIME DEFAULT GETDATE()
        )
      """,
      []
    )

    :ok
  end

  defp create_duckdb_tables(conn) do
    Duckdbex.query(conn, "DROP TABLE IF EXISTS ducks", [])

    Duckdbex.query(
      conn,
      """
        CREATE TABLE ducks (
          age  INTEGER NOT NULL,
          name VARCHAR
        )
      """,
      []
    )

    :ok
  end

  defp create_sqlite_tables(conn) do
    Exqlite.Sqlite3.execute(conn, "DROP TABLE IF EXISTS users")

    Exqlite.Sqlite3.execute(conn, """
      CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        age INTEGER NOT NULL,
        email TEXT,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    """)

    :ok
  end
end
