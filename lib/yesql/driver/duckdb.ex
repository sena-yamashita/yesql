defmodule Yesql.Driver.DuckDB do
  @moduledoc """
  DuckDB用のYesqlドライバー実装

  DuckDBexライブラリを使用してDuckDBデータベースと通信します。

  ## パラメータ処理の適応的アプローチ

  このドライバーは適応的なパラメータ処理を実装しています：

  1. まずネイティブパラメータバインディングを試行
  2. パラメータエラーが発生した場合、自動的に文字列置換にフォールバック
  3. クエリパターンをキャッシュして、2回目以降は最適な方法を即座に選択

  これにより、DuckDBの新しい関数や仕様変更に自動的に対応できます。
  """

  defstruct []

  if match?({:module, _}, Code.ensure_compiled(Duckdbex)) do
    defimpl Yesql.Driver, for: __MODULE__ do
      # ETS tableを使用してクエリパターンをキャッシュ
      @cache_table :yesql_duckdb_query_cache

      def execute(_driver, conn, sql, params) do
        ensure_cache_exists()

        # クエリパターンからキャッシュキーを生成
        cache_key = generate_cache_key(sql)

        case lookup_cache(cache_key) do
          {:ok, :parameterized} ->
            execute_parameterized(conn, sql, params)

          {:ok, :string_replacement} ->
            execute_with_replacement(conn, sql, params)

          :not_found ->
            # キャッシュにない場合は試行してキャッシュに保存
            detect_and_execute(conn, sql, params, cache_key)
        end
      end

      # キャッシュテーブルが存在することを確認
      defp ensure_cache_exists do
        if :ets.whereis(@cache_table) == :undefined do
          :ets.new(@cache_table, [:named_table, :public, :set])
        end
      rescue
        ArgumentError -> :ok
      end

      # クエリパターンからキャッシュキーを生成
      defp generate_cache_key(sql) do
        # パラメータを除いたクエリ構造をキーとして使用
        sql
        |> String.replace(~r/\$\d+/, "?")
        |> String.downcase()
        |> String.trim()
        |> :erlang.phash2()
      end

      # キャッシュから検索
      defp lookup_cache(key) do
        case :ets.lookup(@cache_table, key) do
          [{^key, method}] -> {:ok, method}
          [] -> :not_found
        end
      rescue
        _ -> :not_found
      end

      # 適切な実行方法を検出して実行
      defp detect_and_execute(conn, sql, params, cache_key) do
        case Duckdbex.query(conn, sql, params) do
          {:ok, result_ref} ->
            # パラメータ付きクエリが成功
            :ets.insert(@cache_table, {cache_key, :parameterized})
            fetch_and_format_results(result_ref)

          {:error, error} ->
            # エラーチェックはガード外で行う
            if is_parameter_error?(error) do
              # 文字列置換を試行
              :ets.insert(@cache_table, {cache_key, :string_replacement})
              execute_with_replacement(conn, sql, params)
            else
              {:error, error}
            end

          error ->
            error
        end
      end

      # パラメータ付きクエリを実行
      defp execute_parameterized(conn, sql, params) do
        case Duckdbex.query(conn, sql, params) do
          {:ok, result_ref} ->
            fetch_and_format_results(result_ref)

          error ->
            error
        end
      end

      # 文字列置換を使用してクエリを実行
      defp execute_with_replacement(conn, sql, params) do
        replaced_sql = replace_parameters(sql, params)

        # 複数ステートメントをチェック
        if contains_multiple_statements?(replaced_sql) do
          execute_multiple_statements(conn, replaced_sql)
        else
          case Duckdbex.query(conn, replaced_sql, []) do
            {:ok, result_ref} ->
              fetch_and_format_results(result_ref)

            error ->
              error
          end
        end
      end

      # エラーがパラメータ関連かどうか判定
      defp is_parameter_error?(error_msg) when is_binary(error_msg) do
        # DuckDBのパラメータエラーパターンを検出
        patterns = [
          # 英語のエラーメッセージ
          "Values were not provided",
          "prepared statement parameter",
          "Cannot use positional parameters",
          "Cannot prepare multiple statements",
          "Binder Error",
          "Invalid Input Error",
          "Parser Error: syntax error at or near \"$",
          # パラメータに関連する一般的なキーワード
          "parameter",
          # パラメータ記号そのもの
          "$1",
          "$2",
          "$3"
        ]

        Enum.any?(patterns, &String.contains?(error_msg, &1))
      end

      defp is_parameter_error?(_), do: false

      # 複数ステートメントを含むかチェック
      defp contains_multiple_statements?(sql) do
        # コメントと文字列リテラルを除外してセミコロンを検出
        # 簡易的な実装：末尾以外のセミコロンがあれば複数ステートメント
        trimmed = String.trim(sql)

        # セミコロンで分割して、空でないステートメントが2つ以上あるかチェック
        statements =
          trimmed
          |> String.split(";")
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))

        length(statements) > 1
      end

      # 複数ステートメントを実行
      defp execute_multiple_statements(conn, sql) do
        statements =
          sql
          |> String.split(";")
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))

        # 各ステートメントを順番に実行
        results =
          Enum.reduce_while(statements, {:ok, []}, fn stmt, {:ok, acc} ->
            case Duckdbex.query(conn, stmt, []) do
              {:ok, result_ref} ->
                case fetch_and_format_results(result_ref) do
                  {:ok, result} ->
                    {:cont, {:ok, acc ++ [result]}}

                  error ->
                    {:halt, error}
                end

              error ->
                {:halt, error}
            end
          end)

        # 最後の結果を返す（通常、最後のステートメントの結果が重要）
        case results do
          {:ok, []} -> {:ok, %{rows: [], columns: []}}
          {:ok, all_results} -> {:ok, List.last(all_results)}
          error -> error
        end
      end

      # パラメータを置換
      defp replace_parameters(sql, params) do
        params
        |> Enum.with_index(1)
        |> Enum.reduce(sql, fn {value, idx}, acc ->
          quoted_value = quote_value(value)
          String.replace(acc, "$#{idx}", quoted_value)
        end)
      end

      # 結果を取得してフォーマット
      defp fetch_and_format_results(result_ref) do
        # カラム名を取得
        columns =
          case Duckdbex.columns(result_ref) do
            cols when is_list(cols) -> cols
            _ -> []
          end

        # Duckdbex.fetch_allは直接行を返す（{:ok, rows}ではない）
        rows = Duckdbex.fetch_all(result_ref)

        # DuckDBexの結果形式をPostgrex風の形式に変換
        {:ok, %{rows: rows, columns: columns}}
      rescue
        e ->
          {:error, Exception.message(e)}
      end

      def convert_params(_driver, sql, _param_spec) do
        # 設定されたトークナイザーを使用してSQLトークンを解析
        # DuckDBは$1形式のパラメータを使用
        with {:ok, tokens, _} <- Yesql.TokenizerHelper.tokenize(sql) do
          format_param = fn _param, index -> "$#{index}" end
          Yesql.TokenizerHelper.extract_and_convert_params(tokens, format_param)
        end
      end

      def process_result(_driver, {:ok, result}) do
        case result do
          %{columns: columns, rows: rows} when is_list(rows) ->
            # 行がキーワードリストの場合の処理
            if rows == [] do
              {:ok, []}
            else
              # INSERT/UPDATE/DELETEの結果を特別処理
              # DuckDBは "Count" カラムで影響を受けた行数を返す
              if columns == ["Count"] and length(rows) == 1 do
                {:ok, []}
              else
                case hd(rows) do
                  row when is_list(row) and is_tuple(hd(row)) ->
                    # キーワードリストの場合
                    formatted_rows =
                      Enum.map(rows, fn row ->
                        Enum.into(row, %{})
                      end)

                    {:ok, formatted_rows}

                  _ ->
                    # 通常のリストの場合、カラム名とマッピング
                    if columns && length(columns) > 0 do
                      atom_columns = Enum.map(columns, &to_atom_key/1)

                      formatted_rows =
                        Enum.map(rows, fn row ->
                          atom_columns |> Enum.zip(row) |> Enum.into(%{})
                        end)

                      {:ok, formatted_rows}
                    else
                      # カラム情報がない場合はそのまま返す
                      {:ok, rows}
                    end
                end
              end
            end

          _ ->
            {:error, :invalid_result_format}
        end
      end

      def process_result(_driver, {:error, error}) do
        {:error, error}
      end

      # 文字列またはアトムをアトムに変換
      defp to_atom_key(key) when is_atom(key), do: key
      defp to_atom_key(key) when is_binary(key), do: String.to_atom(key)

      # 値をSQL用にクォート
      defp quote_value(nil), do: "NULL"

      defp quote_value(value) when is_binary(value) do
        # シングルクォートをエスケープして文字列として返す
        escaped = String.replace(value, "'", "''")
        "'#{escaped}'"
      end

      defp quote_value(value) when is_integer(value) or is_float(value) do
        to_string(value)
      end

      defp quote_value(true), do: "TRUE"
      defp quote_value(false), do: "FALSE"
      defp quote_value(%Date{} = date), do: "'#{Date.to_iso8601(date)}'"
      defp quote_value(%DateTime{} = datetime), do: "'#{DateTime.to_iso8601(datetime)}'"
      defp quote_value(%NaiveDateTime{} = datetime), do: "'#{NaiveDateTime.to_iso8601(datetime)}'"
      defp quote_value(%Time{} = time), do: "'#{Time.to_iso8601(time)}'"
      defp quote_value(%Decimal{} = decimal), do: Decimal.to_string(decimal)
      defp quote_value(value), do: "'#{inspect(value)}'"
    end
  end
end
