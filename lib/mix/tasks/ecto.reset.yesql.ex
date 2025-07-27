defmodule Mix.Tasks.Ecto.Reset.Yesql do
  @moduledoc """
  YesQLテスト用のecto.resetタスク
  
  標準のecto.resetと同じく以下を実行：
  1. ecto.drop
  2. ecto.create
  3. ecto.migrate
  4. ecto.seed (seeds.exsがあれば)

  ## 使用方法

      mix ecto.reset.yesql [postgres|mysql|mssql|all]

  ## 例

      # PostgreSQLのみリセット
      MIX_ENV=test mix ecto.reset.yesql postgres

      # 全データベースをリセット
      MIX_ENV=test mix ecto.reset.yesql all
  """

  use Mix.Task

  @shortdoc "YesQLテストデータベースをリセット（drop, create, migrate, seed）"

  def run(args) do
    # テスト環境を設定
    Mix.env(:test)
    
    # アプリケーションを起動
    Application.put_env(:yesql, :env, :test)
    Mix.Task.run("app.start")
    
    repos = case args do
      ["postgres"] -> [Yesql.TestRepo.Postgres]
      ["mysql"] -> [Yesql.TestRepo.MySQL]
      ["mssql"] -> [Yesql.TestRepo.MSSQL]
      ["all"] -> [Yesql.TestRepo.Postgres, Yesql.TestRepo.MySQL, Yesql.TestRepo.MSSQL]
      [] -> [Yesql.TestRepo.Postgres, Yesql.TestRepo.MySQL, Yesql.TestRepo.MSSQL]
      _ ->
        Mix.shell().error("Usage: mix ecto.reset.yesql [postgres|mysql|mssql|all]")
        exit(1)
    end

    for repo <- repos do
      Mix.shell().info("\n=== Resetting #{inspect(repo)} ===")
      
      # 1. Drop
      Mix.shell().info("Dropping database...")
      Mix.Task.run("ecto.drop", ["--repo", to_string(repo)])
      Mix.Task.reenable("ecto.drop")
      
      # 2. Create
      Mix.shell().info("Creating database...")
      Mix.Task.run("ecto.create", ["--repo", to_string(repo)])
      Mix.Task.reenable("ecto.create")
      
      # 3. Migrate
      Mix.shell().info("Running migrations...")
      Mix.Task.run("ecto.migrate", ["--repo", to_string(repo)])
      Mix.Task.reenable("ecto.migrate")
      
      # 4. Seed
      seed_file = "priv/repo/seeds.exs"
      if File.exists?(seed_file) do
        Mix.shell().info("Running seeds...")
        Mix.Task.run("run", [seed_file, "--repo", to_string(repo)])
        Mix.Task.reenable("run")
      end
      
      Mix.shell().info("✅ #{inspect(repo)} reset complete!")
    end
  end
end