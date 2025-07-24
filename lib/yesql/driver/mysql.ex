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
      def convert_params(_driver, sql, param_spec) do
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
        
        # SQLを変換（:param → ?）
        converted_sql = Regex.replace(param_regex, sql, "?")
        
        # param_specからパラメータ名のみのリストを作成
        param_names = case param_spec do
          # 新しい形式: [{:name, index}, ...]
          [{_name, _index} | _] ->
            unique_params
          # 古い形式: [{:name, :type, index}, ...]
          [{_name, _type, _index} | _] ->
            unique_params
          # その他の形式
          _ ->
            unique_params
        end
        
        {converted_sql, param_names}
      end
      
      @doc """
      MySQL結果セットを標準形式に変換します。
      """
      def process_result(_driver, %MyXQL.Result{columns: nil, rows: nil}) do
        {:ok, []}
      end
      
      def process_result(_driver, %MyXQL.Result{columns: columns, rows: rows}) when is_list(rows) do
        result = Enum.map(rows, fn row ->
          columns
          |> Enum.zip(row)
          |> Enum.into(%{}, fn {col, val} -> {String.to_atom(col), val} end)
        end)
        
        {:ok, result}
      end
      
      def process_result(_driver, %MyXQL.Result{} = result) do
        # INSERT/UPDATE/DELETEなどの結果
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