defmodule Yesql.TokenizerBehaviour do
  @moduledoc """
  SQLトークナイザーの動作を定義するビヘイビア。

  異なるトークナイザー実装を切り替えられるようにするため、
  共通のインターフェースを定義します。

  ## トークンの形式

  トークナイザーは以下の形式のトークンを返す必要があります：
  - `{:named_param, atom}` - 名前付きパラメータ（例: `:name` → `{:named_param, :name}`）
  - `{:fragment, binary}` - SQLの断片（パラメータ以外の部分）

  ## 実装例

      defmodule MyApp.CustomTokenizer do
        @behaviour Yesql.TokenizerBehaviour
        
        @impl true
        def tokenize(sql) do
          # カスタムトークナイズロジック
          {:ok, tokens, line_number}
        end
      end
  """

  @doc """
  SQL文字列をトークンに分解します。

  ## パラメータ

    * `sql` - トークナイズするSQL文字列
    
  ## 戻り値

    * `{:ok, tokens, line_number}` - 成功時。トークンのリストと最終行番号
    * `{:error, reason, line_number}` - エラー時。エラー理由と発生行番号
    
  ## トークンの例

      iex> tokenize("SELECT * FROM users WHERE name = :name AND age > :age")
      {:ok, [
        {:fragment, "SELECT * FROM users WHERE name = "},
        {:named_param, :name},
        {:fragment, " AND age > "},
        {:named_param, :age}
      ], 1}
  """
  @callback tokenize(sql :: String.t()) ::
              {:ok, tokens :: list(), line_number :: integer()}
              | {:error, reason :: any(), line_number :: integer()}
end
