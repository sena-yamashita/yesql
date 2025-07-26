defmodule Yesql.Tokenizer.Default do
  @moduledoc """
  Yesqlのデフォルトトークナイザー実装。
  
  既存のLeexベースのトークナイザー（`Yesql.Tokenizer`）をラップして、
  `Yesql.TokenizerBehaviour`に準拠した実装を提供します。
  
  このトークナイザーはSQLの構文（コメントや文字列リテラル）を
  考慮せず、単純に`:param`形式をパラメータとして認識します。
  """
  
  @behaviour Yesql.TokenizerBehaviour
  
  @doc """
  既存のYesql.Tokenizerを使用してSQL文字列をトークナイズします。
  
  ## 注意事項
  
  このトークナイザーは以下の制限があります：
  
  - SQLコメント（`--`, `/* */`）内のパラメータも認識してしまう
  - 文字列リテラル内のパラメータも認識してしまう
  - `:` の後にスペースがある場合にエラーになることがある
  
  より高度な処理が必要な場合は、別のトークナイザー実装を使用してください。
  """
  @impl true
  def tokenize(sql) do
    # 既存のトークナイザーに委譲
    Yesql.Tokenizer.tokenize(sql)
  end
end