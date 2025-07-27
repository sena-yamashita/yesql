defmodule Yesql.Tokenizer.NimbleParsecImpl do
  @moduledoc """
  Nimble Parsec を使用したトークナイザーの実装。

  `Yesql.TokenizerBehaviour` を実装し、SQL コメントと
  文字列リテラルを正しく処理します。

  ## 使用方法

      # 設定
      Yesql.Config.put_tokenizer(Yesql.Tokenizer.NimbleParsecImpl)
      
      # または一時的に使用
      Yesql.Config.with_tokenizer(Yesql.Tokenizer.NimbleParsecImpl, fn ->
        Yesql.parse(sql)
      end)
  """

  @behaviour Yesql.TokenizerBehaviour

  @impl true
  def tokenize(sql) do
    case Yesql.Tokenizer.NimbleParsec.parse_sql(sql) do
      {:ok, tokens, "", %{}, _, _} ->
        # 連続するフラグメントをマージして最適化
        optimized_tokens = merge_fragments(tokens)
        {:ok, optimized_tokens, 1}

      {:error, reason, rest, %{}, {line, _}, offset} ->
        {:error, format_error(reason, rest, offset), line}
    end
  end

  # 連続するフラグメントトークンをマージ
  defp merge_fragments(tokens) do
    tokens
    |> Enum.reduce([], fn
      {:fragment, text}, [{:fragment, prev} | rest] ->
        # 連続するフラグメントをマージ
        [{:fragment, prev <> text} | rest]

      token, acc ->
        [token | acc]
    end)
    |> Enum.reverse()
  end

  defp format_error(reason, rest, offset) do
    context = String.slice(rest, 0, 20)
    "Parse error at position #{offset}: #{inspect(reason)}. Context: #{inspect(context)}"
  end
end
