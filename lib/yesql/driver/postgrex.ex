defmodule Yesql.Driver.Postgrex do
  @moduledoc """
  PostgreSQL用のYesqlドライバー実装
  
  Postgrexライブラリを使用してPostgreSQLデータベースと通信します。
  """
  
  defstruct []
  
  if match?({:module, _}, Code.ensure_compiled(Postgrex)) do
    defimpl Yesql.Driver, for: __MODULE__ do
      def execute(_driver, conn, sql, params) do
        Postgrex.query(conn, sql, params)
      end

      def convert_params(_driver, sql, param_spec) do
        # SQLトークンを解析して名前付きパラメータを$1, $2...形式に変換
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
          %{columns: columns, rows: rows} ->
            atom_columns = Enum.map(columns || [], &String.to_atom/1)
            
            formatted_rows = Enum.map(rows || [], fn row ->
              atom_columns |> Enum.zip(row) |> Enum.into(%{})
            end)
            
            {:ok, formatted_rows}
            
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
    end
  end
end