defmodule Mix.Tasks.Test.Drivers do
  @moduledoc """
  各データベースドライバーのテストを個別に実行します。

  ## 使用方法

      # 全ドライバーのテストを実行
      mix test.drivers

      # 特定のドライバーのみテスト
      mix test.drivers postgresql
      mix test.drivers duckdb
      mix test.drivers mysql

      # 複数のドライバーを指定
      mix test.drivers postgresql duckdb

      # 利用可能なドライバーを表示
      mix test.drivers --list

  ## オプション

    * `--parallel` - 各ドライバーのテストを並列実行（デフォルト: false）
    * `--summary` - サマリーのみ表示
    * `--list` - 利用可能なドライバー一覧を表示

  """
  use Mix.Task

  @shortdoc "データベースドライバーのテストを実行"

  @drivers %{
    "postgresql" => %{
      env: [],
      files: ["test/postgresql*.exs"],
      requires: "PostgreSQL (localhost:5432)"
    },
    "ecto" => %{
      env: [],
      files: ["test/ecto*.exs"],
      requires: "PostgreSQL (localhost:5432) + Ecto設定"
    },
    "duckdb" => %{
      env: [{"DUCKDB_TEST", "true"}],
      files: ["test/duckdb*.exs"],
      requires: "なし（組み込み）"
    },
    "mysql" => %{
      env: [{"MYSQL_TEST", "true"}],
      files: ["test/mysql*.exs"],
      requires: "MySQL (localhost:3306)"
    },
    "sqlite" => %{
      env: [{"SQLITE_TEST", "true"}],
      files: ["test/sqlite*.exs"],
      requires: "なし（組み込み）"
    },
    "mssql" => %{
      env: [{"MSSQL_TEST", "true"}],
      files: ["test/mssql*.exs"],
      requires: "MSSQL (localhost:1433)"
    },
    "oracle" => %{
      env: [{"ORACLE_TEST", "true"}],
      files: ["test/oracle*.exs"],
      requires: "Oracle (localhost:1521)"
    }
  }

  @impl Mix.Task
  def run(args) do
    {opts, drivers, _} = OptionParser.parse(args, switches: [
      parallel: :boolean,
      summary: :boolean,
      list: :boolean
    ])

    if opts[:list] do
      list_drivers()
    else
      # Mixプロジェクトを開始
      Mix.Task.run("app.start")
      
      selected_drivers = if Enum.empty?(drivers) do
        Map.keys(@drivers)
      else
        drivers
      end

      IO.puts("\n🧪 YesQL ドライバーテスト実行")
      IO.puts("=" <> String.duplicate("=", 59))

      if opts[:parallel] do
        run_parallel(selected_drivers, opts)
      else
        run_sequential(selected_drivers, opts)
      end
    end
  end

  defp list_drivers do
    IO.puts("\n利用可能なドライバー:")
    IO.puts(String.duplicate("-", 60))
    
    Enum.each(@drivers, fn {name, config} ->
      IO.puts("  #{String.pad_trailing(name, 12)} - 必要: #{config.requires}")
    end)
    
    IO.puts("\n使用例:")
    IO.puts("  mix test.drivers              # 全てのドライバーをテスト")
    IO.puts("  mix test.drivers postgresql   # PostgreSQLのみテスト")
    IO.puts("  mix test.drivers --parallel   # 並列実行")
  end

  defp run_sequential(drivers, opts) do
    results = Enum.map(drivers, &run_driver_test(&1, opts))
    print_summary(results)
  end

  defp run_parallel(drivers, opts) do
    IO.puts("⚡ 並列実行モード\n")
    
    tasks = Enum.map(drivers, fn driver ->
      Task.async(fn -> run_driver_test(driver, opts) end)
    end)
    
    results = Enum.map(tasks, &Task.await(&1, :infinity))
    print_summary(results)
  end

  defp run_driver_test(driver_name, opts) do
    case Map.get(@drivers, driver_name) do
      nil ->
        IO.puts("❌ 不明なドライバー: #{driver_name}")
        {driver_name, :unknown, 0, 0, 0}
        
      config ->
        unless opts[:summary] do
          IO.puts("\n▶ #{String.upcase(driver_name)} テスト")
          IO.puts("  必要なサービス: #{config.requires}")
        end
        
        start_time = System.monotonic_time(:millisecond)
        
        # テストファイルを検索
        test_files = Enum.flat_map(config.files, &Path.wildcard/1)
        
        if Enum.empty?(test_files) do
          unless opts[:summary] do
            IO.puts("  ⚠️  テストファイルが見つかりません")
          end
          {driver_name, :no_files, 0, 0, 0}
        else
          unless opts[:summary] do
            IO.puts("  ファイル: #{length(test_files)}個")
          end
          
          # 環境変数を設定
          original_env = Enum.map(config.env, fn {key, _} -> {key, System.get_env(key)} end)
          Enum.each(config.env, fn {key, value} -> System.put_env(key, value) end)
          
          try do
            # Mix.Task.run/2 を使ってテストを実行
            exit_code = try do
              Mix.Task.run("test", test_files ++ ["--color"])
              0
            catch
              :exit, {:shutdown, code} -> code
            end
            
            elapsed = System.monotonic_time(:millisecond) - start_time
            
            # 環境変数を元に戻す
            Enum.each(original_env, fn
              {key, nil} -> System.delete_env(key)
              {key, value} -> System.put_env(key, value)
            end)
            
            # 簡易的な結果（詳細は標準出力から）
            status = if exit_code == 0, do: :success, else: :failure
            {driver_name, status, 0, 0, elapsed}
          rescue
            e ->
              IO.puts("  ❌ エラー: #{inspect(e)}")
              {driver_name, :error, 0, 0, 0}
          end
        end
    end
  end

  defp print_summary(results) do
    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("📊 テスト結果サマリー")
    IO.puts(String.duplicate("=", 60))
    
    IO.puts("\nドライバー     | 状態     | 実行時間")
    IO.puts(String.duplicate("-", 40))
    
    Enum.each(results, fn
      {driver, :unknown, _, _, _} ->
        IO.puts("#{String.pad_trailing(driver, 13)} | ❓ 不明  | -")
        
      {driver, :no_files, _, _, _} ->
        IO.puts("#{String.pad_trailing(driver, 13)} | ⚠️  なし  | -")
        
      {driver, :success, _, _, elapsed} ->
        IO.puts("#{String.pad_trailing(driver, 13)} | ✅ 成功  | #{elapsed}ms")
        
      {driver, :failure, _, _, elapsed} ->
        IO.puts("#{String.pad_trailing(driver, 13)} | ❌ 失敗  | #{elapsed}ms")
        
      {driver, :error, _, _, _} ->
        IO.puts("#{String.pad_trailing(driver, 13)} | 💥 エラー | -")
    end)
    
    success_count = Enum.count(results, fn {_, status, _, _, _} -> status == :success end)
    total_count = Enum.count(results, fn {_, status, _, _, _} -> status not in [:unknown, :no_files] end)
    
    IO.puts("\n合計: #{success_count}/#{total_count} 成功")
  end
end