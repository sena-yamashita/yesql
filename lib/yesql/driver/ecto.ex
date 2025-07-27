defmodule Yesql.Driver.Ecto do
  @moduledoc """
  Ecto用のYesqlドライバー実装

  Ectoのリポジトリを通じてデータベースと通信します。
  複数のデータベースアダプターをサポートします。
  """

  defstruct []

  if match?({:module, _}, Code.ensure_compiled(Ecto)) do
    defimpl Yesql.Driver, for: __MODULE__ do
      def execute(_driver, repo, sql, params) do
        Ecto.Adapters.SQL.query(repo, sql, params)
      end

      def convert_params(_driver, sql, _param_spec) do
        # 設定されたトークナイザーを使用してSQLトークンを解析
        # Ectoも基本的にはPostgreSQLと同じ$1, $2...形式を使用
        with {:ok, tokens, _} <- Yesql.TokenizerHelper.tokenize(sql) do
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
