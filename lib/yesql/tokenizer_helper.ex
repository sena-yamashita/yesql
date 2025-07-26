defmodule Yesql.TokenizerHelper do
  @moduledoc """
  トークナイザーを使用するためのヘルパー関数を提供します。
  
  このモジュールは、設定されたトークナイザーを使用して
  SQLをトークナイズし、パラメータ変換を行うための
  共通関数を提供します。
  """
  
  @doc """
  設定されたトークナイザーを使用してSQLをトークナイズします。
  
  `Yesql.Config`で設定されたトークナイザーを自動的に使用します。
  """
  @spec tokenize(String.t()) :: 
    {:ok, list(), integer()} | 
    {:error, any(), integer()}
  def tokenize(sql) do
    tokenizer = Yesql.Config.get_tokenizer()
    tokenizer.tokenize(sql)
  end
  
  @doc """
  トークンからパラメータを抽出し、指定されたフォーマット関数で変換します。
  
  ## パラメータ
  
    * `tokens` - トークナイザーから返されたトークンのリスト
    * `format_param` - パラメータを変換する関数。`(atom, integer) -> String.t()`
    
  ## 戻り値
  
    * `{converted_sql, param_names}` - 変換されたSQLとパラメータ名のリスト
  
  ## 例
  
      tokens = [{:fragment, "SELECT * FROM users WHERE id = "}, {:named_param, :id}]
      format_param = fn _name, index -> "$\#{index}" end
      
      {sql, params} = extract_and_convert_params(tokens, format_param)
      # => {"SELECT * FROM users WHERE id = $1", [:id]}
  """
  @spec extract_and_convert_params(list(), (atom(), integer() -> String.t())) :: 
    {String.t(), list(atom())}
  def extract_and_convert_params(tokens, format_param) when is_function(format_param, 2) do
    {_, query_iodata, params_pairs} =
      tokens
      |> Enum.reduce({1, [], []}, fn
        {:named_param, param}, {i, sql_acc, params_acc} ->
          case params_acc[param] do
            nil ->
              # 新しいパラメータ
              formatted = format_param.(param, i)
              {i + 1, [sql_acc, formatted], [{param, i} | params_acc]}
              
            num ->
              # 既存のパラメータの再利用
              formatted = format_param.(param, num)
              {i, [sql_acc, formatted], params_acc}
          end
          
        {:fragment, fragment}, {i, sql_acc, params_acc} ->
          {i, [sql_acc, fragment], params_acc}
      end)
    
    converted_sql = IO.iodata_to_binary(query_iodata)
    param_names = params_pairs |> Keyword.keys() |> Enum.reverse()
    
    {converted_sql, param_names}
  end
  
  @doc """
  重複を許可してパラメータを抽出・変換します。
  
  MySQLやSQLiteなど、同じパラメータでも出現順にすべて含める必要がある
  データベース用の関数です。
  
  ## 例
  
      tokens = [
        {:fragment, "WHERE name = "}, {:named_param, :name},
        {:fragment, " OR alias = "}, {:named_param, :name}
      ]
      
      {sql, params} = extract_params_with_duplicates(tokens, fn _ -> "?" end)
      # => {"WHERE name = ? OR alias = ?", [:name, :name]}
  """
  @spec extract_params_with_duplicates(list(), (() -> String.t())) :: 
    {String.t(), list(atom())}
  def extract_params_with_duplicates(tokens, format_fn) when is_function(format_fn, 0) do
    param_occurrences = 
      tokens
      |> Enum.with_index()
      |> Enum.filter(fn {token, _} ->
        match?({:named_param, _}, token)
      end)
      |> Enum.map(fn {{:named_param, param}, _idx} ->
        param
      end)
    
    query_iodata = 
      tokens
      |> Enum.map(fn
        {:named_param, _param} -> format_fn.()
        {:fragment, fragment} -> fragment
      end)
    
    converted_sql = IO.iodata_to_binary(query_iodata)
    
    {converted_sql, param_occurrences}
  end
end