defmodule Yesql.Driver.MSSQL do
  @moduledoc """
  Microsoft SQL Serverドライバーの実装。
  
  Tdsライブラリを使用してMicrosoft SQL ServerおよびAzure SQL Databaseをサポートします。
  
  ## パラメータ形式
  
  MSSQLは名前付きパラメータとして `@p1`, `@p2`... を使用します：
  - 入力: `:name`, `:age`
  - 出力: `@p1`, `@p2`...
  
  ## 使用例
  
      defmodule MyApp.Queries do
        use Yesql, driver: :mssql
        
        Yesql.defquery("queries/users.sql")
      end
      
      # 実行
      MyApp.Queries.select_users(conn, name: "Alice", age: 30)
  """
  
  defstruct []
  
  # Tdsがロードされている場合のみプロトコルを実装
  if match?({:module, _}, Code.ensure_compiled(Tds)) do
    defimpl Yesql.Driver, for: __MODULE__ do
      @doc """
      MSSQLクエリを実行します。
      """
      def execute(_driver, conn, sql, params) do
        case Tds.query(conn, sql, params) do
          {:ok, result} ->
            {:ok, result}
          {:error, reason} ->
            {:error, reason}
        end
      end
      
      @doc """
      名前付きパラメータをMSSQLの名前付きパラメータ（@p1, @p2...）に変換します。
      
      ## 例
      
          convert_params(driver, "SELECT * FROM users WHERE name = :name AND age = :age", 
                        [name: "Alice", age: 30])
          # => {"SELECT * FROM users WHERE name = @p1 AND age = @p2", ["Alice", 30]}
      """
      def convert_params(_driver, sql, _param_spec) do
        # 設定されたトークナイザーを使用してSQLトークンを解析
        with {:ok, tokens, _} <- Yesql.TokenizerHelper.tokenize(sql) do
          # MSSQLの@p1, @p2...形式に変換
          format_param = fn _param, index -> "@p#{index}" end
          Yesql.TokenizerHelper.extract_and_convert_params(tokens, format_param)
        end
      end
      
      @doc """
      MSSQL結果セットを標準形式に変換します。
      """
      def process_result(_driver, %Tds.Result{columns: nil, rows: nil}) do
        {:ok, []}
      end
      
      def process_result(_driver, %Tds.Result{columns: columns, rows: rows}) when is_list(rows) do
        # カラム名を文字列からアトムに変換
        column_atoms = Enum.map(columns, &String.to_atom/1)
        
        result = Enum.map(rows, fn row ->
          column_atoms
          |> Enum.zip(row)
          |> Enum.into(%{})
        end)
        
        {:ok, result}
      end
      
      def process_result(_driver, %Tds.Result{} = result) do
        # INSERT/UPDATE/DELETEなどの結果
        {:ok, result}
      end
      
      def process_result(_driver, {:error, _} = error) do
        error
      end
    end
  else
    # Tdsがロードされていない場合のダミー実装
    defimpl Yesql.Driver, for: __MODULE__ do
      def execute(_driver, _conn, _sql, _params) do
        {:error, "Tds is not loaded. Please add {:tds, \"~> 2.3\"} to your dependencies."}
      end
      
      def convert_params(_driver, sql, _param_spec) do
        {sql, []}
      end
      
      def process_result(_driver, _result) do
        {:error, "Tds is not loaded"}
      end
    end
  end
end