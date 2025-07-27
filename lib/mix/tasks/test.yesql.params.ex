defmodule Mix.Tasks.Test.Yesql.Params do
  @moduledoc """
  YesQLのパラメータ変換をテスト・確認するタスク

  ## 使用方法

      # インタラクティブモード（デフォルト）
      mix test.yesql.params

      # 特定のドライバーで変換
      mix test.yesql.params --driver postgresql "SELECT * FROM users WHERE id = :id"
      mix test.yesql.params -d mysql "INSERT INTO logs (level, msg) VALUES (:level, :msg)"

      # 全ドライバーで変換を確認
      mix test.yesql.params --all "SELECT * FROM users WHERE name = :name AND age > :age"

      # ファイルから読み込み
      mix test.yesql.params --file queries/my_query.sql
      mix test.yesql.params --file queries/my_query.sql --driver duckdb
      
      # テストモード（既知の問題をスキップ）
      mix test.yesql.params --test

  ## オプション

    * `-d, --driver` - ドライバーを指定 (postgresql, mysql, mssql, oracle, sqlite, duckdb, ecto)
    * `-a, --all` - 全ドライバーで変換を表示
    * `-f, --file` - SQLファイルから読み込み
    * `--format` - 出力形式 (pretty, simple, json)
    * `--test` - テストモード（既知の問題をスキップ）

  ## 例

      $ mix test.yesql.params -d postgresql "SELECT * FROM users WHERE id = :id"
      
      YesQL Parameter Conversion
      ========================
      
      Driver: PostgreSQL
      
      Original SQL:
      SELECT * FROM users WHERE id = :id
      
      Converted SQL:
      SELECT * FROM users WHERE id = $1
      
      Parameters:
      1. :id → $1

  """
  use Mix.Task

  @shortdoc "YesQLのパラメータ変換をテスト・確認"

  @drivers ~w(postgresql mysql mssql oracle sqlite duckdb ecto)
  
  # 既知の問題（デフォルトトークナイザでは対応できないケース）
  @known_issues %{
    "キャスト構文" => %{
      sql: "SELECT id::integer, name::text FROM users WHERE created_at > :date",
      skip_reason: "デフォルトトークナイザは::キャスト構文に対応していません",
      affected_drivers: :all
    },
    "IN句の配列パラメータ" => %{
      sql: "SELECT * FROM users WHERE id IN (:ids)",
      skip_reason: "配列パラメータの展開はドライバー固有の実装が必要",
      affected_drivers: :all
    },
    "JSONパス演算子" => %{
      sql: "SELECT data->>'name' FROM users WHERE data @> :filter",
      skip_reason: "JSON演算子の解析には高度なトークナイザが必要",
      affected_drivers: [:postgresql]
    },
    "ウィンドウ関数の複雑な構文" => %{
      sql: "SELECT *, ROW_NUMBER() OVER (PARTITION BY :column ORDER BY :order) FROM table",
      skip_reason: "OVER句内のパラメータ解析は現在未対応",
      affected_drivers: :all
    }
  }

  @impl Mix.Task
  def run(args) do
    {opts, sql_parts, _} = OptionParser.parse(args,
      switches: [
        driver: :string,
        all: :boolean,
        file: :string,
        format: :string,
        test: :boolean
      ],
      aliases: [
        d: :driver,
        a: :all,
        f: :file
      ]
    )

    # アプリケーションを起動
    Mix.Task.run("app.start")
    
    # 必要な依存関係を確認
    Application.ensure_all_started(:postgrex)
    Application.ensure_all_started(:ecto)

    cond do
      opts[:test] ->
        handle_test_mode(opts)
        
      opts[:file] ->
        handle_file_mode(opts)
      
      !Enum.empty?(sql_parts) ->
        sql = Enum.join(sql_parts, " ")
        handle_sql_mode(sql, opts)
      
      true ->
        handle_interactive_mode()
    end
  end

  defp handle_test_mode(_opts) do
    IO.puts("\n🧪 YesQL パラメータ変換テスト")
    IO.puts("=" <> String.duplicate("=", 50))
    IO.puts("\n基本的なパラメータ変換のテスト:")
    
    # 基本的なテストケース
    basic_tests = [
      {"単一パラメータ", "SELECT * FROM users WHERE id = :id"},
      {"複数パラメータ", "SELECT * FROM users WHERE name = :name AND age > :age"},
      {"同じパラメータの複数使用", "SELECT * FROM users WHERE created_at > :date AND updated_at < :date"},
      {"ORDER BY句", "SELECT * FROM users ORDER BY :column"},
      {"LIMIT句", "SELECT * FROM users LIMIT :limit OFFSET :offset"}
    ]
    
    IO.puts("")
    
    {passed, failed} = Enum.reduce(basic_tests, {0, 0}, fn {name, sql}, {p, f} ->
      IO.write("  #{String.pad_trailing(name, 30)} ... ")
      
      try do
        {converted, _params} = test_all_drivers(sql)
        if Enum.all?(converted, fn {_, c} -> is_binary(c) end) do
          IO.puts("✅ PASS")
          {p + 1, f}
        else
          IO.puts("❌ FAIL")
          {p, f + 1}
        end
      rescue
        e ->
          IO.puts("❌ ERROR: #{inspect(e)}")
          {p, f + 1}
      end
    end)
    
    IO.puts("\n既知の問題のテスト（スキップ）:")
    
    skipped = Enum.reduce(@known_issues, 0, fn {name, issue}, acc ->
      IO.write("  #{String.pad_trailing(name, 30)} ... ")
      IO.puts("⏭️  SKIP (#{issue.skip_reason})")
      acc + 1
    end)
    
    IO.puts("\n" <> String.duplicate("=", 50))
    IO.puts("テスト結果: #{passed} PASS, #{failed} FAIL, #{skipped} SKIP")
    
    if failed > 0 do
      System.at_exit(fn _ -> exit({:shutdown, 1}) end)
    end
  end
  
  defp test_all_drivers(sql) do
    results = Enum.map(@drivers, fn driver_name ->
      driver_atom = String.to_atom(driver_name)
      # デバッグ: ドライバー名を出力
      # IO.puts("\n    ドライバー名: #{driver_name} -> #{inspect(driver_atom)}")
      case create_driver(driver_atom) do
        {:ok, driver} ->
          try do
            {converted, params} = Yesql.Driver.convert_params(driver, sql, [])
            {driver_name, converted, params}
          rescue
            e ->
              IO.puts("\n    エラー (#{driver_name}): #{inspect(e)}")
              {driver_name, nil, []}
          end
        
        {:error, reason} ->
          IO.puts("\n    ドライバー作成失敗 (#{driver_name}): #{inspect(reason)}")
          {driver_name, nil, []}
      end
    end)
    
    converted = Enum.map(results, fn {driver, conv, _} -> {driver, conv} end)
    params = results |> List.first() |> elem(2)
    
    {converted, params}
  end

  defp handle_file_mode(opts) do
    case File.read(opts[:file]) do
      {:ok, sql} ->
        handle_sql_mode(sql, opts)
      
      {:error, reason} ->
        Mix.shell().error("ファイルを読み込めません: #{opts[:file]} - #{reason}")
    end
  end

  defp handle_sql_mode(sql, opts) do
    format = String.to_atom(opts[:format] || "pretty")
    
    if opts[:all] do
      show_all_drivers(sql, format)
    else
      driver = String.to_atom(opts[:driver] || "postgresql")
      show_single_driver(sql, driver, format)
    end
  end

  defp handle_interactive_mode do
    IO.puts("\n📝 YesQL パラメータ変換チェッカー")
    IO.puts("=" <> String.duplicate("=", 39))
    IO.puts("\n終了するには 'quit' または 'exit' を入力してください。")
    IO.puts("全ドライバーで確認するには 'all: <SQL>' を入力してください。")
    IO.puts("特定のドライバーを使うには '<driver>: <SQL>' を入力してください。")
    IO.puts("\n利用可能なドライバー: #{Enum.join(@drivers, ", ")}")
    
    interactive_loop()
  end

  defp interactive_loop do
    case IO.gets("\n> ") do
      :eof -> :ok
      sql ->
        sql = String.trim(sql)
        
        case sql do
          "quit" -> :ok
          "exit" -> :ok
          "" -> interactive_loop()
          
          _ ->
        case parse_interactive_input(sql) do
          {:all, query} ->
            show_all_drivers(query, :pretty)
          
          {:driver, driver, query} ->
            if driver in @drivers do
              show_single_driver(query, String.to_atom(driver), :pretty)
            else
              IO.puts("❌ 不明なドライバー: #{driver}")
              IO.puts("   利用可能: #{Enum.join(@drivers, ", ")}")
            end
          
            {:query, query} ->
              # デフォルトはPostgreSQL
              show_single_driver(query, :postgresql, :pretty)
          end
          
          interactive_loop()
        end
    end
  end

  defp parse_interactive_input(input) do
    cond do
      String.starts_with?(input, "all:") ->
        query = String.trim_leading(input, "all:") |> String.trim()
        {:all, query}
      
      Regex.match?(~r/^(\w+):/, input) ->
        [_, driver, query] = Regex.run(~r/^(\w+):\s*(.+)$/, input)
        {:driver, driver, query}
      
      true ->
        {:query, input}
    end
  end

  defp show_single_driver(sql, driver_name, format) do
    case create_driver(driver_name) do
      {:ok, driver} ->
        {converted, params} = Yesql.Driver.convert_params(driver, sql, [])
        
        case format do
          :pretty -> pretty_print_single(sql, converted, params, driver_name)
          :simple -> simple_print_single(converted, params)
          :json -> json_print_single(sql, converted, params, driver_name)
          _ -> pretty_print_single(sql, converted, params, driver_name)
        end
      
      {:error, reason} ->
        Mix.shell().error("ドライバー作成エラー: #{reason}")
    end
  end

  defp show_all_drivers(sql, format) do
    results = Enum.map(@drivers, fn driver_name ->
      driver_atom = String.to_atom(driver_name)
      case create_driver(driver_atom) do
        {:ok, driver} ->
          {converted, params} = Yesql.Driver.convert_params(driver, sql, [])
          {driver_name, converted, params}
        
        {:error, _} ->
          {driver_name, "ERROR", []}
      end
    end)
    
    case format do
      :pretty -> pretty_print_all(sql, results)
      :simple -> simple_print_all(results)
      :json -> json_print_all(sql, results)
      _ -> pretty_print_all(sql, results)
    end
  end

  defp create_driver(driver_name) when is_atom(driver_name) do
    Yesql.DriverFactory.create(driver_name)
  end
  
  defp create_driver(driver_name) when is_binary(driver_name) do
    Yesql.DriverFactory.create(String.to_atom(driver_name))
  end

  defp pretty_print_single(original, converted, params, driver_name) do
    IO.puts("\n🔄 YesQL パラメータ変換")
    IO.puts("=" <> String.duplicate("=", 39))
    IO.puts("\nドライバー: #{format_driver_name(driver_name)}")
    IO.puts("\n元のSQL:")
    IO.puts(indent(original))
    IO.puts("\n変換後のSQL:")
    IO.puts(indent(converted))
    
    if params != [] do
      IO.puts("\nパラメータマッピング:")
      params
      |> Enum.with_index(1)
      |> Enum.each(fn {param, idx} ->
        placeholder = get_placeholder(driver_name, idx, param)
        IO.puts("  #{idx}. :#{param} → #{placeholder}")
      end)
    else
      IO.puts("\nパラメータなし")
    end
  end

  defp pretty_print_all(original, results) do
    IO.puts("\n🔄 YesQL パラメータ変換（全ドライバー）")
    IO.puts("=" <> String.duplicate("=", 50))
    IO.puts("\n元のSQL:")
    IO.puts(indent(original))
    
    Enum.each(results, fn {driver, converted, params} ->
      IO.puts("\n#{String.duplicate("-", 50)}")
      IO.puts("#{format_driver_name(String.to_atom(driver))}:")
      IO.puts(indent(converted))
      
      if params != [] do
        IO.puts("パラメータ: #{inspect(params)}")
      end
    end)
  end

  defp simple_print_single(converted, params) do
    IO.puts(converted)
    if params != [], do: IO.puts("# Params: #{inspect(params)}")
  end

  defp simple_print_all(results) do
    Enum.each(results, fn {driver, converted, params} ->
      IO.puts("#{driver}: #{converted}")
      if params != [], do: IO.puts("        Params: #{inspect(params)}")
    end)
  end

  defp json_print_single(original, converted, params, driver_name) do
    Jason.encode!(%{
      driver: driver_name,
      original: original,
      converted: converted,
      parameters: params
    })
    |> IO.puts()
  end

  defp json_print_all(original, results) do
    data = %{
      original: original,
      conversions: Enum.map(results, fn {driver, converted, params} ->
        %{
          driver: driver,
          converted: converted,
          parameters: params
        }
      end)
    }
    
    Jason.encode!(data, pretty: true)
    |> IO.puts()
  end

  defp format_driver_name(driver) do
    case driver do
      :postgresql -> "PostgreSQL"
      :mysql -> "MySQL"
      :mssql -> "MSSQL (SQL Server)"
      :oracle -> "Oracle"
      :sqlite -> "SQLite"
      :duckdb -> "DuckDB"
      :ecto -> "Ecto (PostgreSQL)"
      _ -> to_string(driver)
    end
  end

  defp get_placeholder(driver, idx, _param) do
    case driver do
      d when d in [:postgresql, :duckdb, :ecto] -> "$#{idx}"
      d when d in [:mysql, :sqlite] -> "?"
      :mssql -> "@p#{idx}"
      :oracle -> ":#{idx}"
      _ -> "?#{idx}"
    end
  end

  defp indent(text) do
    text
    |> String.split("\n")
    |> Enum.map(&("  " <> &1))
    |> Enum.join("\n")
  end
end