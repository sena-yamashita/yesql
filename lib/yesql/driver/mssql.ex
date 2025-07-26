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
        # SQLから名前付きパラメータの出現順序を保持して取得
        param_regex = ~r/:([a-zA-Z_][a-zA-Z0-9_]*)/
        
        # すべての名前付きパラメータを出現順に取得
        param_occurrences = Regex.scan(param_regex, sql)
        |> Enum.map(fn [full_match, param_name] -> 
          {full_match, String.to_atom(param_name)}
        end)
        
        # 重複を排除しつつ順序を保持
        unique_params = param_occurrences
        |> Enum.map(&elem(&1, 1))
        |> Enum.uniq()
        
        # パラメータを@p1, @p2...の形式に変換
        param_mapping = unique_params
        |> Enum.with_index(1)
        |> Enum.into(%{}, fn {param, index} -> 
          {param, "@p#{index}"}
        end)
        
        # SQLを変換
        converted_sql = Enum.reduce(param_mapping, sql, fn {param_name, mssql_param}, acc_sql ->
          String.replace(acc_sql, ":#{param_name}", mssql_param)
        end)
        
        # パラメータ値のリストを作成
        param_values = unique_params
        
        {converted_sql, param_values}
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