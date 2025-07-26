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
        
        # パラメータを:1, :2...の形式に変換
        param_mapping = unique_params
        |> Enum.with_index(1)
        |> Enum.into(%{}, fn {param, index} -> 
          {param, ":#{index}"}
        end)
        
        # SQLを変換（:name形式の部分のみを変換、既に:1形式のものは変換しない）
        converted_sql = Enum.reduce(param_mapping, sql, fn {param_name, oracle_param}, acc_sql ->
          # 数字で始まらないパラメータのみ変換（:1, :2などは変換しない）
          String.replace(acc_sql, ~r/:#{param_name}\b/, oracle_param)
        end)
        
        # パラメータ値のリストを作成
        param_values = unique_params
        
        {converted_sql, param_values}
      end
      
      @doc """
      Oracle結果セットを標準形式に変換します。
      """
      def process_result(_driver, %{columns: nil, rows: nil}) do
        {:ok, []}
      end
      
      def process_result(_driver, %{columns: columns, rows: rows}) when is_list(rows) do
        # カラム名を文字列からアトムに変換
        column_atoms = Enum.map(columns, fn col ->
          col
          |> to_string()
          |> String.downcase()
          |> String.to_atom()
        end)
        
        result = Enum.map(rows, fn row ->
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
        {:error, "Jamdb.Oracle is not loaded. Please add {:jamdb_oracle, \"~> 0.5\"} to your dependencies."}
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