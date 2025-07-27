#!/usr/bin/env elixir

# 各ドライバーのローカルテストをまとめて実施するスクリプト

defmodule TestAllDrivers do
  @moduledoc """
  全ドライバーのテストを順次実行し、結果をまとめて表示します。
  """

  @drivers [
    # ドライバー名、環境変数、テストファイルパターン、必要なサービス
    {:postgresql, nil, "test/postgresql*.exs", "PostgreSQL (localhost:5432)"},
    {:ecto, nil, "test/ecto*.exs", "PostgreSQL (localhost:5432)"},
    {:duckdb, "DUCKDB_TEST=true", "test/duckdb*.exs", "なし（組み込み）"},
    {:mysql, "MYSQL_TEST=true", "test/mysql*.exs", "MySQL (localhost:3306)"},
    {:sqlite, "SQLITE_TEST=true", "test/sqlite*.exs", "なし（組み込み）"},
    {:mssql, "MSSQL_TEST=true", "test/mssql*.exs", "MSSQL (localhost:1433)"},
    {:oracle, "ORACLE_TEST=true", "test/oracle*.exs", "Oracle (localhost:1521)"}
  ]

  def run do
    IO.puts("\n=== YesQL 全ドライバーテスト実行 ===\n")
    IO.puts("開始時刻: #{DateTime.utc_now() |> DateTime.to_string()}")
    IO.puts(String.duplicate("=", 60))

    results = 
      @drivers
      |> Enum.map(&run_driver_test/1)
    
    print_summary(results)
  end

  defp run_driver_test({driver, env, pattern, service}) do
    IO.puts("\n▶ #{driver |> to_string() |> String.upcase()} ドライバーテスト")
    IO.puts("  必要なサービス: #{service}")
    
    start_time = System.monotonic_time(:millisecond)
    
    # テストファイルを検索
    test_files = Path.wildcard(pattern)
    
    if Enum.empty?(test_files) do
      IO.puts("  ⚠️  テストファイルが見つかりません: #{pattern}")
      {driver, :no_files, 0, 0, 0}
    else
      IO.puts("  テストファイル: #{Enum.join(test_files, ", ")}")
      
      # 環境変数を設定してテストを実行
      cmd = case env do
        nil -> "mix test #{Enum.join(test_files, " ")} --color"
        env_str -> "#{env_str} mix test #{Enum.join(test_files, " ")} --color"
      end
      
      IO.puts("  実行コマンド: #{cmd}")
      IO.puts("  実行中...")
      
      # テスト実行
      {output, exit_code} = System.cmd("sh", ["-c", cmd], stderr_to_stdout: true)
      
      elapsed = System.monotonic_time(:millisecond) - start_time
      
      # 結果を解析
      {tests, failures, skipped} = parse_test_results(output)
      
      # 結果を表示
      if exit_code == 0 do
        IO.puts("  ✅ 成功: #{tests}テスト, #{failures}失敗, #{skipped}スキップ (#{elapsed}ms)")
      else
        IO.puts("  ❌ 失敗: #{tests}テスト, #{failures}失敗, #{skipped}スキップ (#{elapsed}ms)")
        
        # エラーの詳細を表示
        if String.contains?(output, "connection refused") or String.contains?(output, "could not connect") do
          IO.puts("  ⚠️  データベースに接続できません。サービスが起動していることを確認してください。")
        end
      end
      
      {driver, exit_code, tests, failures, elapsed}
    end
  end

  defp parse_test_results(output) do
    # テスト結果のサマリーを解析
    case Regex.run(~r/(\d+) tests?, (\d+) failures?(?:, (\d+) (?:excluded|skipped))?/, output) do
      [_, tests, failures, skipped] ->
        {String.to_integer(tests), String.to_integer(failures), String.to_integer(skipped || "0")}
      [_, tests, failures] ->
        {String.to_integer(tests), String.to_integer(failures), 0}
      _ ->
        {0, 0, 0}
    end
  end

  defp print_summary(results) do
    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("=== テスト結果サマリー ===\n")
    
    IO.puts("ドライバー     | 状態 | テスト数 | 失敗 | 実行時間")
    IO.puts(String.duplicate("-", 60))
    
    total_tests = 0
    total_failures = 0
    total_time = 0
    
    Enum.each(results, fn
      {driver, :no_files, _, _, _} ->
        IO.puts("#{driver |> to_string() |> String.pad_trailing(13)} | ⚠️   | -        | -    | -")
        
      {driver, 0, tests, failures, elapsed} ->
        total_tests = total_tests + tests
        total_failures = total_failures + failures
        total_time = total_time + elapsed
        IO.puts("#{driver |> to_string() |> String.pad_trailing(13)} | ✅   | #{tests |> to_string() |> String.pad_leading(8)} | #{failures |> to_string() |> String.pad_leading(4)} | #{elapsed}ms")
        
      {driver, _, tests, failures, elapsed} ->
        total_tests = total_tests + tests
        total_failures = total_failures + failures
        total_time = total_time + elapsed
        IO.puts("#{driver |> to_string() |> String.pad_trailing(13)} | ❌   | #{tests |> to_string() |> String.pad_leading(8)} | #{failures |> to_string() |> String.pad_leading(4)} | #{elapsed}ms")
    end)
    
    IO.puts(String.duplicate("-", 60))
    IO.puts("合計           |      | #{total_tests |> to_string() |> String.pad_leading(8)} | #{total_failures |> to_string() |> String.pad_leading(4)} | #{total_time}ms")
    
    IO.puts("\n終了時刻: #{DateTime.utc_now() |> DateTime.to_string()}")
    
    # 全体の成功/失敗を判定
    if total_failures == 0 do
      IO.puts("\n🎉 全てのテストが成功しました！")
    else
      IO.puts("\n⚠️  #{total_failures}個のテストが失敗しました。")
    end
  end
end

# スクリプトを実行
TestAllDrivers.run()