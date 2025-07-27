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
    * `--show-diff` - トークナイザーの動作の違いを表示

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
    {opts, _args, _} =
      OptionParser.parse(args,
        switches: [
          tokenizer: :string,
          all: :boolean,
          sql: :string,
          driver: :string,
          show_diff: :boolean
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
      opts[:show_diff] ->
        # トークナイザーの動作の違いを表示
        show_tokenizer_differences()

      opts[:sql] ->
        # デバッグモード：SQLの変換を確認
        # トークナイザーが指定されていれば設定
        if opts[:tokenizer] do
          case find_tokenizer(opts[:tokenizer]) do
            nil ->
              IO.puts("❌ 不明なトークナイザー: #{opts[:tokenizer]}")
              System.at_exit(fn _ -> exit({:shutdown, 1}) end)

            {_key, _name, module} ->
              Yesql.Config.put_tokenizer(module)
          end
        end

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

    results =
      Enum.map(@tokenizers, fn {key, name, module} ->
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
    total_failed =
      Enum.reduce(results, 0, fn {key, _name, {_total, _passed, failed, _skipped}}, acc ->
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
    # 現在のトークナイザーを環境変数で渡す
    current_tokenizer = Yesql.Config.get_tokenizer()

    tokenizer_name =
      case current_tokenizer do
        Yesql.Tokenizer.NimbleParsecImpl -> "nimble"
        _ -> "default"
      end

    # MIX_ENV=testでdriver_parameter_test.exsを実行
    {output, exit_code} =
      System.cmd("mix", ["test", "test/unit/driver_parameter_test.exs", "--color"],
        env: [
          {"MIX_ENV", "test"},
          {"YESQL_TOKENIZER", tokenizer_name}
        ],
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

    # 現在のトークナイザーを表示
    current_tokenizer = Yesql.Config.get_tokenizer()
    IO.puts("\n現在のトークナイザー: #{inspect(current_tokenizer)}")

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

          Enum.with_index(params, 1)
          |> Enum.each(fn {param, idx} ->
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

  defp show_tokenizer_differences do
    IO.puts("\n🔍 トークナイザーの動作の違い")
    IO.puts("=" <> String.duplicate("=", 60))

    test_cases = [
      {"単一行コメント", "SELECT * FROM users -- :comment_param\nWHERE id = :id"},
      {"複数行コメント", "SELECT * FROM users /* :comment_param1 :comment_param2 */ WHERE id = :id"},
      {"MySQLコメント", "SELECT * FROM users # :comment_param\nWHERE id = :id"},
      {"キャスト構文", "SELECT :id::bigint, :data::jsonb"},
      {"文字列内のパラメータ", "SELECT * FROM logs WHERE message = 'Error: :not_param' AND level = :level"}
    ]

    {:ok, driver} = Yesql.DriverFactory.create(:postgrex)

    Enum.each(test_cases, fn {name, sql} ->
      IO.puts("\n" <> String.duplicate("-", 60))
      IO.puts("📋 " <> name)
      IO.puts("\n元のSQL:")
      IO.puts("  " <> String.replace(sql, "\n", "\n  "))

      # デフォルトトークナイザー
      Yesql.Config.put_tokenizer(Yesql.Tokenizer.Default)
      {default_converted, default_params} = Yesql.Driver.convert_params(driver, sql, [])

      # NimbleParsecトークナイザー
      Yesql.Config.put_tokenizer(Yesql.Tokenizer.NimbleParsecImpl)
      {nimble_converted, nimble_params} = Yesql.Driver.convert_params(driver, sql, [])

      IO.puts("\nDefault (Leex) トークナイザー:")
      IO.puts("  変換後: " <> String.replace(default_converted, "\n", "\n          "))
      IO.puts("  パラメータ: #{inspect(default_params)}")

      IO.puts("\nNimbleParsec トークナイザー:")
      IO.puts("  変換後: " <> String.replace(nimble_converted, "\n", "\n          "))
      IO.puts("  パラメータ: #{inspect(nimble_params)}")

      if default_converted != nimble_converted or default_params != nimble_params do
        IO.puts("\n⚠️  トークナイザーによって結果が異なります")
      end
    end)

    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("\n💡 ポイント:")
    IO.puts("   - NimbleParsecはコメント内のパラメータを正しく無視します")
    IO.puts("   - NimbleParsecはコメント行を完全に削除します")
    IO.puts("   - 両方のトークナイザーはキャスト構文(::)を正しく処理します")
    IO.puts("   - 文字列内の:はパラメータとして扱われません")
  end
end
