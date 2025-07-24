defmodule Yesql.Driver.DuckDB do
  @moduledoc """
  DuckDB用のYesqlドライバー実装
  
  DuckDBexライブラリを使用してDuckDBデータベースと通信します。
  """
  
  defstruct []
  
  if match?({:module, _}, Code.ensure_compiled(Duckdbex)) do
    defimpl Yesql.Driver, for: __MODULE__ do
      def execute(_driver, conn, sql, params) do
        # DuckDBexはコネクションを直接受け取るのではなく、
        # {db, conn}のタプルを期待する場合があるため、適切に処理
        case Duckdbex.query(conn, sql, params) do
          {:ok, result_ref} ->
            # 結果を取得
            case Duckdbex.fetch_all(result_ref) do
              {:ok, rows} ->
                # DuckDBexの結果形式をPostgrex風の形式に変換
                {:ok, %{rows: rows, columns: extract_columns(rows)}}
              error ->
                error
            end
          error ->
            error
        end
      end

      def convert_params(_driver, sql, _param_spec) do
        # DuckDBもPostgreSQLと同じ$1, $2...形式のパラメータを使用
        with {:ok, tokens, _} <- Yesql.Tokenizer.tokenize(sql) do
          {_, query_iodata, params_pairs} =
            tokens
            |> Enum.reduce({1, [], []}, &extract_param/2)

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
      
      # パラメータ抽出のヘルパー関数
      defp extract_param({:named_param, param}, {i, sql, params}) do
        case params[param] do
          nil ->
            {i + 1, [sql, "$#{i}"], [{param, i} | params]}

          num ->
            {i, [sql, "$#{num}"], params}
        end
      end

      defp extract_param({:fragment, fragment}, {i, sql, params}) do
        {i, [sql, fragment], params}
      end
      
      # カラム名からカラム情報を抽出
      defp extract_columns([]), do: []
      defp extract_columns([row | _]) when is_list(row) and is_tuple(hd(row)) do
        # キーワードリストからカラム名を抽出
        Enum.map(row, fn {key, _} -> Atom.to_string(key) end)
      end
      defp extract_columns(_), do: []
      
      # 文字列またはアトムをアトムに変換
      defp to_atom_key(key) when is_atom(key), do: key
      defp to_atom_key(key) when is_binary(key), do: String.to_atom(key)
    end
  end
end