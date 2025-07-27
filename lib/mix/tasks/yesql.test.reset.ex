defmodule Mix.Tasks.Yesql.Test.Reset do
  @moduledoc """
  テストデータベースをリセット（削除して再作成）

  ## 使用方法

      mix yesql.test.reset [postgres|mysql|mssql|all]

  ## 例

      # 全データベースをリセット
      mix yesql.test.reset all

      # PostgreSQLのみリセット
      mix yesql.test.reset postgres
  """

  use Mix.Task

  @shortdoc "テストデータベースをリセット"

  def run(args) do
    Mix.env(:test)
    
    db_type = case args do
      ["postgres"] -> :postgres
      ["mysql"] -> :mysql
      ["mssql"] -> :mssql
      ["all"] -> :all
      [] -> :all
      _ ->
        Mix.shell().error("Usage: mix yesql.test.reset [postgres|mysql|mssql|all]")
        exit(1)
    end

    # アプリケーションを起動
    {:ok, _} = Application.ensure_all_started(:ecto_sql)
    
    repos = case db_type do
      :postgres -> [Yesql.TestRepo.Postgres]
      :mysql -> [Yesql.TestRepo.MySQL]
      :mssql -> [Yesql.TestRepo.MSSQL]
      :all -> [Yesql.TestRepo.Postgres, Yesql.TestRepo.MySQL, Yesql.TestRepo.MSSQL]
    end

    Mix.shell().info("Resetting test databases...")

    Enum.each(repos, fn repo ->
      Mix.shell().info("\n=== #{inspect(repo)} ===")
      
      # リポジトリの設定を取得
      config = Application.get_env(:yesql, repo, [])
      
      if config != [] do
        # 1. データベースを削除
        Mix.shell().info("Dropping database...")
        adapter = repo.__adapter__()
        
        case adapter.storage_down(config) do
          :ok ->
            Mix.shell().info("✓ Database dropped")
          {:error, :already_down} ->
            Mix.shell().info("✓ Database already dropped")
          {:error, reason} ->
            Mix.shell().error("✗ Failed to drop database: #{inspect(reason)}")
        end
      else
        Mix.shell().error("No configuration found for #{inspect(repo)}")
      end
    end)

    # セットアップを実行
    Mix.shell().info("\nRunning setup...")
    Mix.Tasks.Yesql.Test.Setup.run(args)
  end
end