defmodule Mix.Tasks.Yesql.Test.Setup do
  @moduledoc """
  Ectoを使用してテスト環境をセットアップする

  ## 使用方法

      mix yesql.test.setup [postgres|mysql|mssql|all]

  ## 例

      # 全データベースをセットアップ
      mix yesql.test.setup all

      # PostgreSQLのみセットアップ
      mix yesql.test.setup postgres

  ## 動作

  1. データベースを作成（mix ecto.create）
  2. マイグレーションを実行（mix ecto.migrate）
  3. シードデータを投入（mix run priv/repo/seeds.exs）
  """

  use Mix.Task

  @shortdoc "Ectoを使用してテストデータベースをセットアップ"

  def run(args) do
    # テスト環境を設定
    Mix.env(:test)
    
    # アプリケーションを起動して設定を読み込む
    Application.ensure_all_started(:yesql)
    
    # 明示的に設定を読み込む
    if File.exists?("config/test.exs") do
      Config.Reader.read!("config/test.exs")
      |> Application.put_all_env()
    end
    
    db_type = case args do
      ["postgres"] -> :postgres
      ["mysql"] -> :mysql
      ["mssql"] -> :mssql
      ["all"] -> :all
      [] -> :all
      _ ->
        Mix.shell().error("Usage: mix yesql.test.setup [postgres|mysql|mssql|all]")
        exit(1)
    end

    # アプリケーションを起動
    {:ok, _} = Application.ensure_all_started(:postgrex)
    {:ok, _} = Application.ensure_all_started(:myxql)
    {:ok, _} = Application.ensure_all_started(:tds)
    {:ok, _} = Application.ensure_all_started(:ecto_sql)
    
    repos = case db_type do
      :postgres -> [Yesql.TestRepo.Postgres]
      :mysql -> [Yesql.TestRepo.MySQL]
      :mssql -> [Yesql.TestRepo.MSSQL]
      :all -> [Yesql.TestRepo.Postgres, Yesql.TestRepo.MySQL, Yesql.TestRepo.MSSQL]
    end

    Mix.shell().info("Setting up test databases...")

    Enum.each(repos, fn repo ->
      Mix.shell().info("\n=== #{inspect(repo)} ===")
      
      # リポジトリの設定を取得
      config = Application.get_env(:yesql, repo, [])
      
      if config != [] do
        setup_repo(repo, config)
      else
        Mix.shell().error("No configuration found for #{inspect(repo)}")
        Mix.shell().error("Make sure config/test.exs is loaded")
      end
    end)

    Mix.shell().info("\n✅ Test setup completed!")
  end

  defp setup_repo(repo, config) do
    # 1. データベースを作成
    Mix.shell().info("Creating database...")
    case create_database(repo, config) do
      :ok ->
        Mix.shell().info("✓ Database created or already exists")
      {:error, reason} ->
        Mix.shell().error("✗ Failed to create database: #{inspect(reason)}")
        :error
    end
    
    # 2. リポジトリを起動
    case repo.start_link() do
      {:ok, _pid} ->
        Mix.shell().info("✓ Repository started")
      {:error, {:already_started, _pid}} ->
        Mix.shell().info("✓ Repository already running")
      {:error, reason} ->
        Mix.shell().error("✗ Failed to start repository: #{inspect(reason)}")
        :error
    end
    
    # 3. マイグレーションを実行
    Mix.shell().info("Running migrations...")
    
    # 共通マイグレーション
    Ecto.Migrator.run(repo, "priv/repo/migrations", :up, all: true)
    
    # データベース固有のマイグレーション
    case repo do
      Yesql.TestRepo.Postgres ->
        Ecto.Migrator.run(repo, "priv/repo/postgres/migrations", :up, all: true)
      _ ->
        :ok
    end
    
    Mix.shell().info("✓ Migrations completed")
    
    # 4. シードデータを投入
    Mix.shell().info("Seeding data...")
    seed_path = "priv/repo/seeds.exs"
    
    if File.exists?(seed_path) do
      Code.eval_file(seed_path)
      Mix.shell().info("✓ Seed data inserted")
    else
      Mix.shell().info("No seed file found at #{seed_path}")
    end
  end

  defp create_database(repo, config) do
    adapter = repo.__adapter__()
    
    case adapter.storage_up(config) do
      :ok -> :ok
      {:error, :already_up} -> :ok
      error -> error
    end
  end
end