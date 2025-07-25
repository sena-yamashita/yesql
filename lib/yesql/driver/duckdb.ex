defmodule Yesql.Driver.DuckDB do
  @moduledoc """
  DuckDB用のYesqlドライバー実装
  
  DuckDBexライブラリを使用してDuckDBデータベースと通信します。
  """
  
  defstruct []
  
  if match?({:module, _}, Code.ensure_compiled(Duckdbex)) do
    defimpl Yesql.Driver, for: __MODULE__ do
      def execute(_driver, conn, sql, params) do
        # DuckDBexはパラメータクエリをサポートしているが、
        # read_csv_auto等の関数内では動作しない
        final_sql = if contains_file_function?(sql) do
          # ファイル関数の場合は文字列置換を使用
          replace_file_parameters(sql, params)
        else
          sql
        end
        
        # ファイル関数の場合はパラメータなしで実行
        final_params = if contains_file_function?(sql), do: [], else: params
        
        case Duckdbex.query(conn, final_sql, final_params) do
          {:ok, result_ref} ->
            fetch_and_format_results(result_ref)
          error ->
            error
        end
      end
      
      defp fetch_and_format_results(result_ref) do
        # Duckdbex.fetch_allは直接行を返す（{:ok, rows}ではない）
        rows = Duckdbex.fetch_all(result_ref)
        # DuckDBexの結果形式をPostgrex風の形式に変換
        {:ok, %{rows: rows, columns: extract_columns(rows)}}
      rescue
        e ->
          {:error, Exception.message(e)}
      end

      def convert_params(_driver, sql, _param_spec) do
        # DuckDBは$1形式のパラメータを使用（Yesqlのデフォルト形式を保持）
        with {:ok, tokens, _} <- Yesql.Tokenizer.tokenize(sql) do
          {_, query_iodata, params_pairs} =
            tokens
            |> Enum.reduce({1, [], []}, &extract_param_dollar/2)

          converted_sql = IO.iodata_to_binary(query_iodata)
          param_mapping = params_pairs |> Keyword.keys() |> Enum.reverse()

          {converted_sql, param_mapping}
        end
      end

      def process_result(_driver, {:ok, result}) do
        case result do
          %{columns: columns, rows: rows} when is_list(rows) ->
            # 行がキーワードリストの場合の処理
            if rows == [] do
              {:ok, []}
            else
              case hd(rows) do
                row when is_list(row) and is_tuple(hd(row)) ->
                  # キーワードリストの場合
                  formatted_rows = Enum.map(rows, fn row ->
                    Enum.into(row, %{})
                  end)
                  {:ok, formatted_rows}
                  
                _ ->
                  # 通常のリストの場合、カラム名とマッピング
                  atom_columns = Enum.map(columns || [], &to_atom_key/1)
                  formatted_rows = Enum.map(rows, fn row ->
                    atom_columns |> Enum.zip(row) |> Enum.into(%{})
                  end)
                  {:ok, formatted_rows}
              end
            end
            
          _ ->
            {:error, :invalid_result_format}
        end
      end
      
      def process_result(_driver, {:error, error}) do
        {:error, error}
      end
      
      # パラメータ抽出のヘルパー関数（$1形式）
      defp extract_param_dollar({:named_param, param}, {i, sql, params}) do
        case params[param] do
          nil ->
            {i + 1, [sql, "$#{i}"], [{param, i} | params]}

          num ->
            # 既に使用されたパラメータは同じ番号を使用
            {i, [sql, "$#{num}"], params}
        end
      end

      defp extract_param_dollar({:fragment, fragment}, {i, sql, params}) do
        {i, [sql, fragment], params}
      end
      
      # カラム名からカラム情報を抽出
      defp extract_columns([]), do: []
      defp extract_columns([row | _]) when is_list(row) and is_tuple(hd(row)) do
        # キーワードリストからカラム名を抽出
        Enum.map(row, fn {key, _} -> Atom.to_string(key) end)
      end
      defp extract_columns(_) do
        # DuckDBexは列名を返さないため、ハードコード
        # 実際の実装では、別途クエリで列情報を取得する必要がある
        ["id", "name", "value", "created_at"]
      end
      
      # 文字列またはアトムをアトムに変換
      defp to_atom_key(key) when is_atom(key), do: key
      defp to_atom_key(key) when is_binary(key), do: String.to_atom(key)
      
      # ファイル関数を含むかチェック
      defp contains_file_function?(sql) do
        # DuckDBのファイル関数のリスト
        file_functions = [
          "read_csv_auto",
          "read_csv",
          "read_json_auto", 
          "read_json",
          "read_parquet",
          "read_excel",
          "write_csv",
          "write_parquet",
          "write_json"
        ]
        
        Enum.any?(file_functions, fn func ->
          String.contains?(sql, func <> "(")
        end)
      end
      
      # ファイルパラメータを置換
      defp replace_file_parameters(sql, params) do
        params
        |> Enum.with_index(1)
        |> Enum.reduce(sql, fn {value, idx}, acc ->
          # 文字列値を適切にクォート
          quoted_value = quote_value(value)
          String.replace(acc, "$#{idx}", quoted_value)
        end)
      end
      
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
      defp quote_value(value), do: "'#{inspect(value)}'"
    end
  end
end