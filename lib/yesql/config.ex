defmodule Yesql.Config do
  @moduledoc """
  Yesqlの設定管理モジュール。
  
  アプリケーション設定やプロセス辞書を使用して、
  トークナイザーなどの設定を管理します。
  
  ## 設定方法
  
  ### アプリケーション設定（config.exs）
  
      config :yesql,
        tokenizer: MyApp.CustomTokenizer
  
  ### 実行時設定
  
      Yesql.Config.put_tokenizer(MyApp.CustomTokenizer)
  
  ### 一時的な設定
  
      Yesql.Config.with_tokenizer(MyApp.CustomTokenizer, fn ->
        # このブロック内でのみカスタムトークナイザーが使用される
        Yesql.parse(sql)
      end)
  """
  
  @default_tokenizer Yesql.Tokenizer.Default
  @tokenizer_key :yesql_tokenizer
  
  @doc """
  現在設定されているトークナイザーモジュールを取得します。
  
  優先順位：
  1. プロセス辞書
  2. アプリケーション設定
  3. デフォルト（`Yesql.Tokenizer.Default`）
  """
  @spec get_tokenizer() :: module()
  def get_tokenizer do
    case Process.get(@tokenizer_key) do
      nil ->
        Application.get_env(:yesql, :tokenizer, @default_tokenizer)
      tokenizer ->
        tokenizer
    end
  end
  
  @doc """
  トークナイザーモジュールを設定します。
  
  この設定は現在のプロセスにのみ適用されます。
  """
  @spec put_tokenizer(module()) :: :ok
  def put_tokenizer(tokenizer) when is_atom(tokenizer) do
    Process.put(@tokenizer_key, tokenizer)
    :ok
  end
  
  @doc """
  トークナイザー設定をリセットします。
  
  プロセス辞書から設定を削除し、アプリケーション設定または
  デフォルトに戻します。
  """
  @spec reset_tokenizer() :: :ok
  def reset_tokenizer do
    Process.delete(@tokenizer_key)
    :ok
  end
  
  @doc """
  指定されたトークナイザーを使用して関数を実行します。
  
  関数の実行後、トークナイザー設定は元に戻されます。
  
  ## 例
  
      Yesql.Config.with_tokenizer(MyApp.CommentAwareTokenizer, fn ->
        Yesql.parse("SELECT * FROM users -- :comment_param")
      end)
  """
  @spec with_tokenizer(module(), (() -> result)) :: result when result: any()
  def with_tokenizer(tokenizer, fun) when is_atom(tokenizer) and is_function(fun, 0) do
    old_tokenizer = Process.get(@tokenizer_key)
    
    try do
      put_tokenizer(tokenizer)
      fun.()
    after
      case old_tokenizer do
        nil -> reset_tokenizer()
        _ -> put_tokenizer(old_tokenizer)
      end
    end
  end
  
  @doc """
  指定されたモジュールが有効なトークナイザーかどうかを確認します。
  
  モジュールが`Yesql.TokenizerBehaviour`を実装しているかチェックします。
  """
  @spec valid_tokenizer?(module()) :: boolean()
  def valid_tokenizer?(module) when is_atom(module) do
    Code.ensure_loaded?(module) and
      function_exported?(module, :tokenize, 1)
  end
end