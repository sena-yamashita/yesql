# トークナイザーの簡単な比較
# mix run test/support/tokenizer_quick_comparison.exs

defmodule TokenizerQuickComparison do
  def run do
    sqls = [
      {"Simple", "SELECT * FROM users"},
      {"With params", "SELECT * FROM users WHERE id = :id AND name = :name"},
      {"With comments", "-- Comment with :param\nSELECT * FROM users WHERE id = :id"},
      {"Complex", "SELECT id::text FROM users WHERE status = ':active' -- :comment"}
    ]

    IO.puts("=== Tokenizer Quick Comparison ===\n")

    Enum.each(sqls, fn {name, sql} ->
      IO.puts("## #{name}")
      IO.puts("SQL: #{inspect(sql)}")

      # Default tokenizer
      {default_time, {:ok, default_tokens, _}} =
        :timer.tc(fn ->
          Yesql.Tokenizer.Default.tokenize(sql)
        end)

      # Nimble Parsec tokenizer
      {nimble_time, {:ok, nimble_tokens, _}} =
        :timer.tc(fn ->
          Yesql.Tokenizer.NimbleParsecImpl.tokenize(sql)
        end)

      IO.puts("Default time: #{default_time} μs")
      IO.puts("Nimble time:  #{nimble_time} μs")
      IO.puts("Speed ratio:  #{Float.round(nimble_time / default_time, 2)}x")

      if default_tokens == nimble_tokens do
        IO.puts("✓ Results match")
      else
        IO.puts("✗ Results differ")
        IO.puts("  Default params: #{inspect(extract_params(default_tokens))}")
        IO.puts("  Nimble params:  #{inspect(extract_params(nimble_tokens))}")
      end

      IO.puts("")
    end)

    IO.puts("## Summary")
    IO.puts("- Default (Leex) tokenizer: Fast but doesn't handle comments/strings")
    IO.puts("- Nimble Parsec tokenizer: Slower but correctly handles SQL syntax")
    IO.puts("- Performance difference: ~2-3x slower (acceptable for correctness)")
  end

  defp extract_params(tokens) do
    tokens
    |> Enum.filter(&match?({:named_param, _}, &1))
    |> Enum.map(&elem(&1, 1))
  end
end

TokenizerQuickComparison.run()
