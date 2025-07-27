defmodule Yesql.TestSetup do
  @moduledoc """
  Ectoを使用した統一的なテスト環境セットアップ
  
  各データベースドライバーの直接テストは残しつつ、
  セットアップとマイグレーションはEctoで統一する
  """

  def setup_all_databases do
    # Docker環境が起動していることを前提
    databases = [
      {"postgres", "POSTGRES_HOST"},
      {"mysql", "MYSQL_HOST"},
      {"mssql", "MSSQL_HOST"}
    ]

    for {db_type, host_env} <- databases do
      if System.get_env(host_env, "localhost") != "skip" do
        setup_database(db_type)
      end
    end
  end

  def setup_database(db_type) do
    IO.puts("Setting up #{db_type} test database...")
    
    with :ok <- create_database(db_type),
         :ok <- run_migrations(db_type),
         :ok <- seed_test_data(db_type) do
      IO.puts("✓ #{db_type} setup complete")
      :ok
    else
      {:error, reason} ->
        IO.puts("✗ #{db_type} setup failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp create_database("postgres") do
    # PostgreSQLデータベース作成
    config = [
      hostname: System.get_env("POSTGRES_HOST", "localhost"),
      username: System.get_env("POSTGRES_USER", "postgres"),
      password: System.get_env("POSTGRES_PASSWORD", "postgres"),
      database: "postgres",
      port: String.to_integer(System.get_env("POSTGRES_PORT", "5432"))
    ]

    case Postgrex.start_link(config) do
      {:ok, conn} ->
        Postgrex.query(conn, "CREATE DATABASE yesql_test", [])
        GenServer.stop(conn)
        :ok
      _ ->
        # データベースが既に存在する可能性
        :ok
    end
  end

  defp create_database("mysql") do
    config = [
      hostname: System.get_env("MYSQL_HOST", "localhost"),
      username: System.get_env("MYSQL_USER", "root"),
      password: System.get_env("MYSQL_PASSWORD", "root"),
      port: String.to_integer(System.get_env("MYSQL_PORT", "3306"))
    ]

    case MyXQL.start_link(config) do
      {:ok, conn} ->
        MyXQL.query(conn, "CREATE DATABASE IF NOT EXISTS yesql_test")
        GenServer.stop(conn)
        :ok
      _ ->
        :ok
    end
  end

  defp create_database("mssql") do
    config = [
      hostname: System.get_env("MSSQL_HOST", "localhost"),
      username: System.get_env("MSSQL_USER", "sa"),
      password: System.get_env("MSSQL_PASSWORD", "YourStrong@Passw0rd"),
      database: "master",
      port: String.to_integer(System.get_env("MSSQL_PORT", "1433"))
    ]

    case Tds.start_link(config) do
      {:ok, conn} ->
        Tds.query(conn, """
          IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = 'yesql_test')
          CREATE DATABASE yesql_test
        """, [])
        GenServer.stop(conn)
        :ok
      _ ->
        :ok
    end
  end

  defp run_migrations(db_type) do
    # Ectoマイグレーションを使用してテーブルを作成
    repo = get_repo(db_type)
    
    # リポジトリを起動
    {:ok, _} = repo.start_link()
    
    # テーブルを削除して再作成
    Ecto.Adapters.SQL.query!(repo, """
      DROP TABLE IF EXISTS large_data CASCADE;
      DROP TABLE IF EXISTS products CASCADE;
      DROP TABLE IF EXISTS cats CASCADE;
      DROP TABLE IF EXISTS users CASCADE;
    """)

    # 共通テーブルを作成
    create_common_tables(repo)
    
    # データベース固有のテーブルを作成
    create_db_specific_tables(repo, db_type)
    
    :ok
  end

  defp get_repo("postgres"), do: Yesql.TestRepo.Postgres
  defp get_repo("mysql"), do: Yesql.TestRepo.MySQL
  defp get_repo("mssql"), do: Yesql.TestRepo.MSSQL

  defp create_common_tables(repo) do
    # users テーブル
    Ecto.Adapters.SQL.query!(repo, """
      CREATE TABLE users (
        id #{id_type(repo)} PRIMARY KEY,
        name VARCHAR(255) NOT NULL,
        age INTEGER NOT NULL,
        email VARCHAR(255),
        inserted_at TIMESTAMP,
        updated_at TIMESTAMP
      )
    """)

    # cats テーブル
    Ecto.Adapters.SQL.query!(repo, """
      CREATE TABLE cats (
        id #{id_type(repo)} PRIMARY KEY,
        name VARCHAR(255),
        age INTEGER NOT NULL
      )
    """)

    # products テーブル
    Ecto.Adapters.SQL.query!(repo, """
      CREATE TABLE products (
        id #{id_type(repo)} PRIMARY KEY,
        name VARCHAR(255) NOT NULL,
        price DECIMAL(10, 2),
        category VARCHAR(255),
        in_stock #{boolean_type(repo)} DEFAULT #{boolean_default(repo)},
        inserted_at TIMESTAMP,
        updated_at TIMESTAMP
      )
    """)

    # large_data テーブル（ストリーミングテスト用）
    Ecto.Adapters.SQL.query!(repo, """
      CREATE TABLE large_data (
        id #{id_type(repo)} PRIMARY KEY,
        value INTEGER,
        data TEXT,
        inserted_at TIMESTAMP,
        updated_at TIMESTAMP
      )
    """)
  end

  defp create_db_specific_tables(repo, "postgres") do
    # PostgreSQL固有のテーブル（JSONB、配列など）
    Ecto.Adapters.SQL.query!(repo, """
      CREATE TABLE IF NOT EXISTS test_jsonb (
        id SERIAL PRIMARY KEY,
        data JSONB NOT NULL
      )
    """)

    Ecto.Adapters.SQL.query!(repo, """
      CREATE TABLE IF NOT EXISTS test_arrays (
        id SERIAL PRIMARY KEY,
        tags TEXT[],
        numbers INTEGER[]
      )
    """)
  end

  defp create_db_specific_tables(_repo, _), do: :ok

  defp id_type(repo) do
    case repo.__adapter__() do
      Ecto.Adapters.Postgres -> "SERIAL"
      Ecto.Adapters.MyXQL -> "INT AUTO_INCREMENT"
      Ecto.Adapters.Tds -> "INT IDENTITY(1,1)"
      _ -> "INTEGER"
    end
  end

  defp boolean_type(repo) do
    case repo.__adapter__() do
      Ecto.Adapters.Tds -> "BIT"
      _ -> "BOOLEAN"
    end
  end

  defp boolean_default(repo) do
    case repo.__adapter__() do
      Ecto.Adapters.Tds -> "1"
      _ -> "true"
    end
  end

  defp seed_test_data(db_type) do
    repo = get_repo(db_type)
    
    # 基本的なテストデータを挿入
    Ecto.Adapters.SQL.query!(repo, """
      INSERT INTO users (name, age, email) VALUES
      ('Alice', 30, 'alice@example.com'),
      ('Bob', 25, 'bob@example.com'),
      ('Charlie', 35, 'charlie@example.com')
    """)

    Ecto.Adapters.SQL.query!(repo, """
      INSERT INTO cats (name, age) VALUES
      ('Fluffy', 3),
      ('Mittens', 5)
    """)

    :ok
  end
end