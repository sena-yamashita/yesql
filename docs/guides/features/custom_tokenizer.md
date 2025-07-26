# カスタムトークナイザーの実装

Yesql v2.0からトークナイザーを切り替え可能になりました。これにより、SQLコメントや文字列リテラルを適切に処理するカスタムトークナイザーを実装できます。

## デフォルトトークナイザーの制限

デフォルトのトークナイザーには以下の制限があります：

- SQLコメント（`--`, `/* */`, `#`）内のパラメータも認識してしまう
- 文字列リテラル内のパラメータも認識してしまう
- `:` の後にスペースがある場合にエラーになることがある

```sql
-- このSQLはエラーになる可能性があります
-- name: find_users  -- :name がパラメータとして認識される
SELECT * FROM users WHERE id = :id
```

## カスタムトークナイザーの実装

### 1. Behaviourの実装

カスタムトークナイザーは`Yesql.TokenizerBehaviour`を実装する必要があります：

```elixir
defmodule MyApp.CommentAwareTokenizer do
  @behaviour Yesql.TokenizerBehaviour
  
  @impl true
  def tokenize(sql) do
    # コメントと文字列リテラルを考慮したトークナイズ処理
    sql
    |> remove_comments()
    |> tokenize_with_strings()
  end
  
  defp remove_comments(sql) do
    # SQLコメントを除去する処理
    sql
    |> remove_single_line_comments()
    |> remove_multi_line_comments()
  end
  
  defp remove_single_line_comments(sql) do
    # -- コメントと # コメントを処理
    Regex.replace(~r/--.*$|#.*$/m, sql, "")
  end
  
  defp remove_multi_line_comments(sql) do
    # /* */ コメントを処理
    Regex.replace(~r/\/\*.*?\*\//s, sql, " ")
  end
  
  defp tokenize_with_strings(sql) do
    # 文字列リテラルを考慮してトークナイズ
    # 実装の詳細...
    {:ok, tokens, 1}
  end
end
```

### 2. トークナイザーの設定

#### アプリケーション設定（config.exs）

```elixir
config :yesql,
  tokenizer: MyApp.CommentAwareTokenizer
```

#### 実行時設定

```elixir
# グローバルに設定（現在のプロセスのみ）
Yesql.Config.put_tokenizer(MyApp.CommentAwareTokenizer)

# 一時的に使用
Yesql.Config.with_tokenizer(MyApp.CommentAwareTokenizer, fn ->
  # このブロック内でのみカスタムトークナイザーが使用される
  Yesql.parse(sql)
end)
```

## トークンの形式

トークナイザーは以下の形式のトークンを返す必要があります：

- `{:named_param, atom}` - 名前付きパラメータ
- `{:fragment, binary}` - SQLの断片

例：
```elixir
[
  {:fragment, "SELECT * FROM users WHERE id = "},
  {:named_param, :id},
  {:fragment, " AND name = "},
  {:named_param, :name}
]
```

## 実装例：正規表現ベースのトークナイザー

コメントを考慮しない、シンプルな正規表現ベースのトークナイザー：

```elixir
defmodule MyApp.RegexTokenizer do
  @behaviour Yesql.TokenizerBehaviour
  
  @impl true
  def tokenize(sql) do
    # 正規表現でパラメータを検出
    parts = Regex.split(~r/:([a-zA-Z_][a-zA-Z0-9_]*)/, sql, include_captures: true)
    
    tokens = parts
    |> Enum.chunk_every(2)
    |> Enum.flat_map(fn
      [fragment, ":" <> param] ->
        [{:fragment, fragment}, {:named_param, String.to_atom(param)}]
      [fragment] ->
        [{:fragment, fragment}]
    end)
    |> Enum.reject(fn
      {:fragment, ""} -> true
      _ -> false
    end)
    
    {:ok, tokens, 1}
  end
end
```

## 高度な例：AST ベースのトークナイザー

より高度な実装では、SQL パーサーライブラリを使用してASTを構築し、
正確にパラメータを抽出できます：

```elixir
defmodule MyApp.AstTokenizer do
  @behaviour Yesql.TokenizerBehaviour
  
  @impl true
  def tokenize(sql) do
    case SqlParser.parse(sql) do
      {:ok, ast} ->
        tokens = extract_tokens_from_ast(ast, sql)
        {:ok, tokens, 1}
      {:error, reason} ->
        # フォールバック：デフォルトトークナイザーを使用
        Yesql.Tokenizer.Default.tokenize(sql)
    end
  end
  
  defp extract_tokens_from_ast(ast, original_sql) do
    # ASTをトラバースしてパラメータ位置を特定
    # 元のSQLと照合してトークンを生成
    # ...
  end
end
```

## テスト

カスタムトークナイザーのテスト例：

```elixir
defmodule MyApp.CommentAwareTokenizerTest do
  use ExUnit.Case
  
  test "コメント内のパラメータを無視する" do
    sql = """
    -- This query finds users by :name
    SELECT * FROM users WHERE id = :id
    """
    
    {:ok, tokens, _} = MyApp.CommentAwareTokenizer.tokenize(sql)
    
    # :name は無視され、:id のみがパラメータとして認識される
    assert Enum.count(tokens, &match?({:named_param, _}, &1)) == 1
    assert {:named_param, :id} in tokens
  end
  
  test "文字列リテラル内のパラメータを無視する" do
    sql = "SELECT * FROM users WHERE comment = ':not_param' AND id = :id"
    
    {:ok, tokens, _} = MyApp.CommentAwareTokenizer.tokenize(sql)
    
    # 文字列内の :not_param は無視される
    assert Enum.count(tokens, &match?({:named_param, _}, &1)) == 1
    assert {:named_param, :id} in tokens
  end
end
```

## パフォーマンス考慮事項

1. **キャッシング**: トークナイズ結果をキャッシュすることを検討
2. **フォールバック**: エラー時にデフォルトトークナイザーにフォールバック
3. **ストリーミング**: 大きなSQLファイルに対応するためのストリーミング処理

## まとめ

カスタムトークナイザーを実装することで、以下が可能になります：

- SQLコメントの適切な処理
- 文字列リテラルの考慮
- データベース固有の構文への対応
- より柔軟なパラメータ記法のサポート

デフォルトトークナイザーで問題がある場合は、要件に応じたカスタムトークナイザーの実装を検討してください。