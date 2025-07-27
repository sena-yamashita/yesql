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

      def convert_params(_driver, sql, _param_spec) do
        # 設定されたトークナイザーを使用してSQLトークンを解析
        with {:ok, tokens, _} <- Yesql.TokenizerHelper.tokenize(sql) do
          # PostgreSQLの$1, $2...形式に変換
          format_param = fn _param, index -> "$#{index}" end
          Yesql.TokenizerHelper.extract_and_convert_params(tokens, format_param)
        end
      end

      def process_result(_driver, {:ok, result}) do
        case result do
          %{columns: columns, rows: rows} ->
            atom_columns = Enum.map(columns || [], &String.to_atom/1)

            formatted_rows =
              Enum.map(rows || [], fn row ->
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
    end
  end
end
