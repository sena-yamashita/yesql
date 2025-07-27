defmodule Yesql.Driver.MySQL do
  @moduledoc """
  MySQL/MariaDBドライバーの実装。

  MyXQLライブラリを使用してMySQLおよびMariaDBデータベースをサポートします。

  ## パラメータ形式

  MySQLは位置パラメータとして `?` を使用します：
  - 入力: `:name`, `:age`
  - 出力: `?`, `?`

  ## 使用例

      defmodule MyApp.Queries do
        use Yesql, driver: :mysql
        
        Yesql.defquery("queries/users.sql")
      end
      
      # 実行
      MyApp.Queries.select_users(conn, name: "Alice", age: 30)
  """

  defstruct []

  # MyXQLがロードされている場合のみプロトコルを実装
  if match?({:module, _}, Code.ensure_compiled(MyXQL)) do
    defimpl Yesql.Driver, for: __MODULE__ do
      @doc """
      MySQLクエリを実行します。
      """
      def execute(_driver, conn, sql, params) do
        case MyXQL.query(conn, sql, params) do
          {:ok, result} ->
            {:ok, result}

          {:error, reason} ->
            {:error, reason}
        end
      end

      @doc """
      名前付きパラメータをMySQLの位置パラメータ（?）に変換します。

      ## 例

          convert_params(driver, "SELECT * FROM users WHERE name = :name AND age = :age", 
                        [name: "Alice", age: 30])
          # => {"SELECT * FROM users WHERE name = ? AND age = ?", ["Alice", 30]}
      """
      def convert_params(_driver, sql, _param_spec) do
        # 設定されたトークナイザーを使用してSQLトークンを解析
        with {:ok, tokens, _} <- Yesql.TokenizerHelper.tokenize(sql) do
          # MySQLの?形式に変換（重複を許可）
          format_fn = fn -> "?" end
          Yesql.TokenizerHelper.extract_params_with_duplicates(tokens, format_fn)
        end
      end

      @doc """
      MySQL結果セットを標準形式に変換します。
      """
      def process_result(_driver, {:ok, %MyXQL.Result{columns: nil, rows: nil} = result}) do
        # INSERT/UPDATE/DELETEなどの結果
        {:ok, result}
      end

      def process_result(_driver, {:ok, %MyXQL.Result{columns: columns, rows: rows}})
          when is_list(rows) and is_list(columns) do
        result =
          Enum.map(rows, fn row ->
            columns
            |> Enum.zip(row)
            |> Enum.into(%{}, fn {col, val} -> {String.to_atom(col), val} end)
          end)

        {:ok, result}
      end

      def process_result(_driver, {:ok, %MyXQL.Result{} = result}) do
        # その他の結果（columnsやrowsがnilでない場合も含む）
        {:ok, result}
      end

      def process_result(_driver, {:error, _} = error) do
        error
      end
    end
  else
    # MyXQLがロードされていない場合のダミー実装
    defimpl Yesql.Driver, for: __MODULE__ do
      def execute(_driver, _conn, _sql, _params) do
        {:error, "MyXQL is not loaded. Please add {:myxql, \"~> 0.6\"} to your dependencies."}
      end

      def convert_params(_driver, sql, param_spec) do
        {sql, []}
      end

      def process_result(_driver, _result) do
        {:error, "MyXQL is not loaded"}
      end
    end
  end
end
