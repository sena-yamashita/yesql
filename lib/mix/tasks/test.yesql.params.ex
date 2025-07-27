defmodule Mix.Tasks.Test.Yesql.Params do
  @moduledoc """
  YesQLのパラメータ変換をテスト・確認するタスク

  ## 使用方法

      # driver_parameter_test.exsをデフォルトトークナイザで実行
      mix test.yesql.params

      # 特定のトークナイザでテスト実行
      mix test.yesql.params --tokenizer nimble
      mix test.yesql.params -t nimble

      # 全トークナイザでテスト実行
      mix test.yesql.params --all

      # 特定のSQLのパラメータ変換を確認（デバッグ用）
      mix test.yesql.params --sql "SELECT * FROM users WHERE id = :id"
      mix test.yesql.params --sql "SELECT * FROM users WHERE id = :id" --driver postgresql

  ## オプション

    * `-t, --tokenizer` - トークナイザを指定 (default, nimble)
    * `-a, --all` - 全トークナイザでテストを実行
    * `--sql` - 特定のSQLの変換を確認（デバッグ用）
    * `-d, --driver` - SQLデバッグ時のドライバー指定

  ## 例

      # 全トークナイザでパラメータテストを実行
      $ mix test.yesql.params --all
      
      🧪 YesQL パラメータ変換テスト
      ============================================================
      
      Default (Leex) トークナイザ:
        基本テスト: 42 passed
        複雑な構文: 3 passed, 2 failed
      
      NimbleParsec トークナイザ:
        基本テスト: 42 passed
        複雑な構文: 5 passed, 0 failed

  """
  use Mix.Task

  @shortdoc "YesQLのパラメータ変換をテスト・確認"

  @tokenizers [
    {:default, "Default (Leex)", Yesql.Tokenizer.Default},
    {:nimble, "NimbleParsec", Yesql.Tokenizer.NimbleParsecImpl}
  ]

  @impl Mix.Task
  def run(args) do
    {opts, _args, _} = OptionParser.parse(args,
      switches: [
        tokenizer: :string,
        all: :boolean,
        sql: :string,
        driver: :string
      ],
      aliases: [
        t: :tokenizer,
        a: :all,
        d: :driver
      ]
    )

    # アプリケーションを起動
    Mix.Task.run("app.start")
    
    cond do
      opts[:sql] ->
        # デバッグモード：SQLの変換を確認
        debug_sql_conversion(opts[:sql], opts[:driver] || "postgresql")
        
      opts[:all] ->
        # 全トークナイザでテスト実行
        run_all_tokenizer_tests()
        
      true ->
        # 指定されたトークナイザでテスト実行
        tokenizer_name = opts[:tokenizer] || "default"
        run_single_tokenizer_test(tokenizer_name)
    end
  end

  defp run_all_tokenizer_tests do
    IO.puts("\n🧪 YesQL パラメータ変換テスト")
    IO.puts("=" <> String.duplicate("=", 60))
    
    results = Enum.map(@tokenizers, fn {key, name, module} ->
      IO.puts("\n" <> String.duplicate("-", 60))
      IO.puts("#{name} トークナイザ:")
      IO.puts(String.duplicate("-", 60))
      
      # トークナイザを設定
      Yesql.Config.put_tokenizer(module)
      
      # driver_parameter_test.exsを実行
      result = run_parameter_tests()
      
      # 結果を表示
      display_test_results(result)
      
      {key, name, result}
    end)
    
    # サマリー表示
    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("📊 テスト結果サマリー")
    IO.puts(String.duplicate("=", 60))
    
    Enum.each(results, fn {_key, name, {total, passed, failed, skipped}} ->
      IO.puts("\n#{name}:")
      IO.puts("  合計: #{total} tests")
      IO.puts("  成功: #{passed} passed")
      if failed > 0 do
        IO.puts("  失敗: #{failed} failed")
      end
      if skipped > 0 do
        IO.puts("  スキップ: #{skipped} skipped")
      end
    end)
    
    # 失敗があるか確認
    total_failed = Enum.reduce(results, 0, fn {key, _name, {_total, _passed, failed, _skipped}}, acc ->
      # nimbleはすべてパスすべき
      if key == :nimble and failed > 0 do
        acc + failed
      else
        acc
      end
    end)
    
    if total_failed > 0 do
      System.at_exit(fn _ -> exit({:shutdown, 1}) end)
    end
  end

  defp run_single_tokenizer_test(tokenizer_name) do
    case find_tokenizer(tokenizer_name) do
      nil ->
        IO.puts("❌ 不明なトークナイザ: #{tokenizer_name}")
        IO.puts("   利用可能: default, nimble")
        System.at_exit(fn _ -> exit({:shutdown, 1}) end)
        
      {_key, name, module} ->
        IO.puts("\n🧪 YesQL パラメータ変換テスト - #{name}")
        IO.puts("=" <> String.duplicate("=", 60))
        
        # トークナイザを設定
        Yesql.Config.put_tokenizer(module)
        
        # driver_parameter_test.exsを実行
        result = run_parameter_tests()
        
        # 結果を表示
        display_test_results(result)
        
        {_total, _passed, failed, _skipped} = result
        if failed > 0 and tokenizer_name == "nimble" do
          System.at_exit(fn _ -> exit({:shutdown, 1}) end)
        end
    end
  end

  defp find_tokenizer(name) do
    Enum.find(@tokenizers, fn {key, _name, _module} ->
      to_string(key) == name
    end)
  end

  defp run_parameter_tests do
    # MIX_ENV=testでdriver_parameter_test.exsを実行
    {output, exit_code} = System.cmd("mix", ["test", "test/unit/driver_parameter_test.exs", "--color"],
      env: [{"MIX_ENV", "test"}],
      stderr_to_stdout: true
    )
    
    # 結果を解析
    parse_test_output(output, exit_code)
  end

  defp parse_test_output(output, _exit_code) do
    # テスト結果のサマリーを解析
    total = extract_number(output, ~r/(\d+) tests?/)
    failed = extract_number(output, ~r/(\d+) failures?/)
    skipped = extract_number(output, ~r/(\d+) (?:excluded|skipped)/)
    
    # passedの計算を修正
    passed = total - failed - skipped
    
    # tokenizer_dependentタグのテストをカウント（将来の拡張用）
    _tokenizer_dependent_failed = if output =~ "tokenizer_dependent" do
      # 複雑な構文テストの失敗数をカウント
      Regex.scan(~r/\d+\) test .+? \(.*?tokenizer_dependent.*?\).*?\n.*?Assertion.*?failed/s, output)
      |> length()
    else
      0
    end
    
    {total, passed, failed, skipped}
  end

  defp extract_number(output, regex) do
    case Regex.run(regex, output) do
      [_, number] -> String.to_integer(number)
      _ -> 0
    end
  end

  defp display_test_results({total, passed, failed, skipped}) do
    IO.puts("\n結果:")
    IO.puts("  合計: #{total} tests")
    IO.puts("  成功: #{passed} passed")
    if failed > 0 do
      IO.puts("  失敗: #{failed} failed")
    end
    if skipped > 0 do
      IO.puts("  スキップ: #{skipped} skipped")
    end
  end

  defp debug_sql_conversion(sql, driver_name) do
    IO.puts("\n🔍 SQL変換デバッグ")
    IO.puts("=" <> String.duplicate("=", 40))
    
    driver_atom = String.to_atom(driver_name)
    case Yesql.DriverFactory.create(driver_atom) do
      {:ok, driver} ->
        IO.puts("\nドライバー: #{driver_name}")
        IO.puts("\n元のSQL:")
        IO.puts("  #{sql}")
        
        try do
          {converted, params} = Yesql.Driver.convert_params(driver, sql, [])
          IO.puts("\n変換後のSQL:")
          IO.puts("  #{converted}")
          IO.puts("\nパラメータ:")
          Enum.with_index(params, 1) |> Enum.each(fn {param, idx} ->
            IO.puts("  #{idx}. :#{param}")
          end)
        rescue
          e ->
            IO.puts("\n❌ エラー: #{inspect(e)}")
        end
        
      {:error, reason} ->
        IO.puts("\n❌ ドライバー作成エラー: #{reason}")
    end
  end
end