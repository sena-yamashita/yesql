# 単一のSQLファイルのトークナイズテスト

sql = """
-- name: simple_query
SELECT * FROM users WHERE id = :id
"""

IO.puts("Testing SQL:")
IO.puts(sql)

case Yesql.Tokenizer.tokenize(sql) do
  {:ok, tokens} ->
    IO.puts("\nTokens:")
    IO.inspect(tokens)
  {:error, error} ->
    IO.puts("\nError:")
    IO.inspect(error)
end

# ファイルからの読み込みもテスト
IO.puts("\n\nTesting from file:")
case File.read("test/sql/postgresql/simple_test.sql") do
  {:ok, content} ->
    IO.puts("File content:")
    IO.inspect(content)
    case Yesql.Tokenizer.tokenize(content) do
      {:ok, tokens} ->
        IO.puts("\nFile tokens:")
        IO.inspect(tokens)
      {:error, error} ->
        IO.puts("\nFile error:")
        IO.inspect(error)
    end
  _ ->
    IO.puts("File read error")
end