defmodule Yesql.Driver.Oracle do
  @moduledoc """
  Oracleデータベースドライバーの実装。

  jamdb_oracleライブラリを使用してOracle DatabaseおよびOracle Cloudをサポートします。

  ## パラメータ形式

  Oracleはネイティブの位置パラメータとして `:1`, `:2`... を使用します：
  - 入力: `:name`, `:age`
  - 出力: `:1`, `:2`...

  ## 使用例

      defmodule MyApp.Queries do
        use Yesql, driver: :oracle
        
        Yesql.defquery("queries/users.sql")
      end
      
      # 実行
      MyApp.Queries.select_users(conn, name: "Alice", age: 30)
  """

  defstruct []

  # Jamdb.Oracleがロードされている場合のみプロトコルを実装
  if match?({:module, _}, Code.ensure_compiled(Jamdb.Oracle)) do
    defimpl Yesql.Driver, for: __MODULE__ do
      @doc """
      Oracleクエリを実行します。
      """
      def execute(_driver, conn, sql, params) do
        case Jamdb.Oracle.query(conn, sql, params) do
          {:ok, result} ->
            {:ok, result}

          {:error, reason} ->
            {:error, reason}
        end
      end

      @doc """
      名前付きパラメータをOracleの位置パラメータ（:1, :2...）に変換します。

      ## 例

          convert_params(driver, "SELECT * FROM users WHERE name = :name AND age = :age", 
                        [name: "Alice", age: 30])
          # => {"SELECT * FROM users WHERE name = :1 AND age = :2", ["Alice", 30]}
      """
      def convert_params(_driver, sql, _param_spec) do
        # 設定されたトークナイザーを使用してSQLトークンを解析
        with {:ok, tokens, _} <- Yesql.TokenizerHelper.tokenize(sql) do
          # Oracleの:1, :2...形式に変換
          format_param = fn _param, index -> ":#{index}" end
          Yesql.TokenizerHelper.extract_and_convert_params(tokens, format_param)
        end
      end

      @doc """
      Oracle結果セットを標準形式に変換します。
      """
      def process_result(_driver, %{columns: nil, rows: nil}) do
        {:ok, []}
      end

      def process_result(_driver, %{columns: columns, rows: rows}) when is_list(rows) do
        # カラム名を文字列からアトムに変換
        column_atoms =
          Enum.map(columns, fn col ->
            col
            |> to_string()
            |> String.downcase()
            |> String.to_atom()
          end)

        result =
          Enum.map(rows, fn row ->
            column_atoms
            |> Enum.zip(row)
            |> Enum.into(%{})
          end)

        {:ok, result}
      end

      def process_result(_driver, %{num_rows: _num_rows} = result) do
        # INSERT/UPDATE/DELETEなどの結果
        {:ok, result}
      end

      def process_result(_driver, {:error, _} = error) do
        error
      end
    end
  else
    # Jamdb.Oracleがロードされていない場合のダミー実装
    defimpl Yesql.Driver, for: __MODULE__ do
      def execute(_driver, _conn, _sql, _params) do
        {:error,
         "Jamdb.Oracle is not loaded. Please add {:jamdb_oracle, \"~> 0.5\"} to your dependencies."}
      end

      def convert_params(_driver, sql, _param_spec) do
        {sql, []}
      end

      def process_result(_driver, _result) do
        {:error, "Jamdb.Oracle is not loaded"}
      end
    end
  end
end
