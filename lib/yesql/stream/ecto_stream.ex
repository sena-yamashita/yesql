if Code.ensure_loaded?(Ecto) do
  defmodule Yesql.Stream.EctoStream do
    @moduledoc """
    Ecto用のストリーミング実装

    Ecto.Repo.streamを活用して、大規模データセットを
    効率的にストリーミング処理します。

    ## 使用例

        # トランザクション内でのストリーミング
        {:ok, stream} = Yesql.Stream.EctoStream.create(MyApp.Repo, sql, params)
        
        MyApp.Repo.transaction(fn ->
          stream
          |> Stream.map(&process_row/1)
          |> Stream.run()
        end)

    ## 注意事項

    - Ecto.Repo.streamはトランザクション内でのみ動作します
    - PostgreSQL/MySQLなどのSQLアダプターが必要です
    - :max_rowsオプションでチャンクサイズを制御できます（デフォルト: 500）
    """

    @doc """
    Ecto用のストリームを作成

    ## オプション

      * `:max_rows` - 一度に取得する行数（デフォルト: 500）
      * `:prefix` - クエリを実行するプレフィックス（スキーマ/データベース）
      * `:timeout` - クエリタイムアウト（ミリ秒）
      * `:log` - ログを出力するか（デフォルト: true）
    """
    def create(repo, sql, params, opts \\ []) do
      max_rows = Keyword.get(opts, :max_rows, 500)
      prefix = Keyword.get(opts, :prefix)
      timeout = Keyword.get(opts, :timeout, 15_000)
      log = Keyword.get(opts, :log, true)

      # Ectoドライバーのパラメータ変換を使用
      driver = %Yesql.Driver.Ecto{}
      {converted_sql, param_mapping} = Yesql.Driver.convert_params(driver, sql, [])

      # パラメータをマッピング
      ordered_params =
        case params do
          params when is_list(params) ->
            params

          params when is_map(params) ->
            Enum.map(param_mapping, &Map.get(params, &1))
        end

      # ストリームオプション
      stream_opts = [
        max_rows: max_rows,
        timeout: timeout,
        log: log
      ]

      stream_opts =
        if prefix do
          Keyword.put(stream_opts, :prefix, prefix)
        else
          stream_opts
        end

      # Ecto.Repo.streamを使用
      stream = repo.stream(converted_sql, ordered_params, stream_opts)

      # 結果を変換
      transformed_stream =
        Stream.map(stream, fn row ->
          # Ectoの結果形式をYesqlの形式に変換
          row
        end)

      {:ok, transformed_stream}
    rescue
      e ->
        {:error, e}
    end

    @doc """
    トランザクション内でストリーミング処理を実行

    ## 例

        {:ok, result} = Yesql.Stream.EctoStream.transaction_stream(
          MyApp.Repo,
          "SELECT * FROM users WHERE active = $1",
          [true],
          fn row ->
            # 各行を処理
            IO.inspect(row)
          end
        )
    """
    def transaction_stream(repo, sql, params, process_fn, opts \\ []) do
      isolation_level = Keyword.get(opts, :isolation_level, :read_committed)

      repo.transaction(
        fn ->
          case create(repo, sql, params, opts) do
            {:ok, stream} ->
              count =
                stream
                |> Stream.map(fn row ->
                  process_fn.(row)
                  1
                end)
                |> Enum.sum()

              {:ok, count}

            error ->
              repo.rollback(error)
          end
        end,
        isolation: isolation_level
      )
    end

    @doc """
    バッチ処理でストリーミング

    ## 例

        {:ok, batch_count} = Yesql.Stream.EctoStream.batch_process(
          MyApp.Repo,
          "SELECT * FROM large_table",
          [],
          1000,
          fn batch ->
            # バッチを処理
            Enum.each(batch, &process_row/1)
          end
        )
    """
    def batch_process(repo, sql, params, batch_size, process_fn, opts \\ []) do
      repo.transaction(fn ->
        case create(repo, sql, params, opts) do
          {:ok, stream} ->
            batch_count =
              stream
              |> Stream.chunk_every(batch_size)
              |> Stream.map(fn batch ->
                process_fn.(batch)
                1
              end)
              |> Enum.sum()

            {:ok, batch_count}

          error ->
            repo.rollback(error)
        end
      end)
    end

    @doc """
    カーソルベースのストリーミング（トランザクション不要）

    大規模データセットを扱う際に、トランザクションなしで
    ストリーミング処理を行いたい場合に使用します。

    ## 注意

    - ORDER BY句が必須です
    - プライマリキーまたはユニークなカラムでのソートが推奨されます
    """
    def cursor_based_stream(repo, sql, params, cursor_column, opts \\ []) do
      chunk_size = Keyword.get(opts, :chunk_size, 1000)

      Stream.resource(
        fn -> {nil, true} end,
        fn {last_cursor, continue} ->
          if continue do
            # カーソルクエリを構築
            cursor_sql = build_cursor_query(sql, cursor_column, last_cursor)

            # クエリ実行
            case Ecto.Adapters.SQL.query(repo, cursor_sql, params ++ [chunk_size]) do
              {:ok, %{rows: rows, columns: columns}} when rows != [] ->
                # 結果を変換
                atom_columns = Enum.map(columns, &String.to_atom/1)

                results =
                  Enum.map(rows, fn row ->
                    Enum.zip(atom_columns, row) |> Enum.into(%{})
                  end)

                # 次のカーソル位置を取得
                last_row = List.last(results)
                next_cursor = Map.get(last_row, cursor_column)

                # 結果が chunk_size より少ない場合は終了
                continue = length(results) == chunk_size

                {results, {next_cursor, continue}}

              _ ->
                {:halt, nil}
            end
          else
            {:halt, nil}
          end
        end,
        fn _ -> :ok end
      )
    end

    @doc """
    並列ストリーミング処理

    複数のワーカーでデータを並列処理します。
    """
    def parallel_stream(repo, sql, params, opts \\ []) do
      parallelism = Keyword.get(opts, :parallelism, System.schedulers_online())
      chunk_size = Keyword.get(opts, :chunk_size, 1000)

      repo.transaction(fn ->
        case create(repo, sql, params, opts) do
          {:ok, stream} ->
            # ストリームを並列処理用にチャンク化
            stream
            |> Stream.chunk_every(chunk_size * parallelism)
            |> Task.async_stream(
              fn chunk ->
                # 各チャンクを並列処理
                chunk
                |> Enum.chunk_every(chunk_size)
                |> Enum.map(fn batch ->
                  # バッチごとに処理
                  {length(batch), batch}
                end)
              end,
              max_concurrency: parallelism,
              timeout: :infinity
            )
            |> Stream.flat_map(fn {:ok, results} -> results end)

          error ->
            repo.rollback(error)
        end
      end)
    end

    # プライベート関数

    defp build_cursor_query(sql, cursor_column, nil) do
      # 初回のクエリ
      """
      #{sql}
      ORDER BY #{cursor_column}
      LIMIT $#{next_param_number(sql)}
      """
    end

    defp build_cursor_query(sql, cursor_column, _last_cursor) do
      # カーソル以降のデータを取得
      """
      WITH cursor_query AS (
        #{sql}
      )
      SELECT * FROM cursor_query
      WHERE #{cursor_column} > $#{next_param_number(sql)}
      ORDER BY #{cursor_column}
      LIMIT $#{next_param_number(sql) + 1}
      """
    end

    defp next_param_number(sql) do
      # SQL内の最大パラメータ番号を取得
      ~r/\$(\d+)/
      |> Regex.scan(sql)
      |> Enum.map(fn [_, num] -> String.to_integer(num) end)
      |> Enum.max(fn -> 0 end)
      |> then(&(&1 + 1))
    end
  end
end
