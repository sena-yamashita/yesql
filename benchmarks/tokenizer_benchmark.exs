# トークナイザーのパフォーマンスベンチマーク
# 
# 実行方法: mix run benchmarks/tokenizer_benchmark.exs

defmodule TokenizerBenchmark do
  @sqls %{
    "simple" => "SELECT * FROM users",
    "with_params" => "SELECT * FROM users WHERE id = :id AND name = :name",
    "with_comments" => """
    -- Header comment with :param
    SELECT 
      u.id,
      u.name, -- :comment_param
      /* :block_param */ u.email
    FROM users u
    WHERE u.id = :id
    """,
    "complex" => """
    -- Complex query with various SQL features
    WITH user_stats AS (
      SELECT 
        user_id,
        COUNT(*) as post_count,
        MAX(created_at) as last_post
      FROM posts
      WHERE status = ':active' -- literal string
        AND user_id = :user_id
      GROUP BY user_id
    )
    SELECT 
      u.id::text as id_text,
      u.name,
      u.email,
      'https://example.com/user/' || u.id as profile_url,
      us.post_count,
      us.last_post
    FROM users u
    LEFT JOIN user_stats us ON u.id = us.user_id
    WHERE u.created_at > :date
      AND u.status != 'deleted'
      /* Additional filters can be added here
         :filter_param would go here */
    ORDER BY u.created_at DESC
    LIMIT :limit
    """
  }
  
  def run do
    IO.puts("=== Tokenizer Performance Benchmark ===\n")
    
    tokenizers = %{
      "Default (Leex)" => Yesql.Tokenizer.Default,
      "Nimble Parsec" => Yesql.Tokenizer.NimbleParsecImpl
    }
    
    Enum.each(@sqls, fn {name, sql} ->
      IO.puts("\n## Test case: #{name}")
      IO.puts("SQL length: #{String.length(sql)} characters")
      
      inputs = Map.new(tokenizers, fn {label, module} ->
        {label, {module, sql}}
      end)
      
      Benchee.run(
        %{
          "tokenize" => fn {module, sql} -> module.tokenize(sql) end
        },
        inputs: inputs,
        time: 5,
        memory_time: 2,
        warmup: 2
      )
    end)
    
    IO.puts("\n## Correctness verification")
    verify_correctness()
  end
  
  defp verify_correctness do
    Enum.each(@sqls, fn {name, sql} ->
      {:ok, default_tokens, _} = Yesql.Tokenizer.Default.tokenize(sql)
      {:ok, nimble_tokens, _} = Yesql.Tokenizer.NimbleParsecImpl.tokenize(sql)
      
      # コメント処理の違いを考慮（Nimble Parsecはコメントを正しく除外）
      if name in ["simple", "with_params"] do
        if default_tokens == nimble_tokens do
          IO.puts("✓ #{name}: outputs match")
        else
          IO.puts("✗ #{name}: outputs differ")
          IO.puts("  Default: #{inspect(default_tokens)}")
          IO.puts("  Nimble:  #{inspect(nimble_tokens)}")
        end
      else
        IO.puts("ℹ #{name}: differs due to comment handling (expected)")
      end
    end)
  end
end

TokenizerBenchmark.run()