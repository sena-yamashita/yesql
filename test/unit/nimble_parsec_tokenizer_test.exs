defmodule Yesql.Unit.NimbleParsecTokenizerTest do
  use ExUnit.Case, async: true

  @moduletag :unit

  alias Yesql.Tokenizer.NimbleParsecImpl

  describe "基本的なトークナイズ" do
    test "シンプルなSQL" do
      sql = "SELECT * FROM users"
      {:ok, tokens, _} = NimbleParsecImpl.tokenize(sql)

      assert tokens == [{:fragment, "SELECT * FROM users"}]
    end

    test "パラメータ付きSQL" do
      sql = "SELECT * FROM users WHERE id = :id"
      {:ok, tokens, _} = NimbleParsecImpl.tokenize(sql)

      assert tokens == [
               {:fragment, "SELECT * FROM users WHERE id = "},
               {:named_param, :id}
             ]
    end

    test "複数パラメータ" do
      sql = "SELECT * FROM users WHERE name = :name AND age > :age"
      {:ok, tokens, _} = NimbleParsecImpl.tokenize(sql)

      assert tokens == [
               {:fragment, "SELECT * FROM users WHERE name = "},
               {:named_param, :name},
               {:fragment, " AND age > "},
               {:named_param, :age}
             ]
    end
  end

  describe "コメント処理" do
    test "単一行コメント" do
      sql = """
      -- This is a comment with :param
      SELECT * FROM users WHERE id = :id
      """

      {:ok, tokens, _} = NimbleParsecImpl.tokenize(sql)

      assert tokens == [
               {:fragment, "SELECT * FROM users WHERE id = "},
               {:named_param, :id},
               {:fragment, "\n"}
             ]
    end

    test "複数行コメント" do
      sql = """
      /* This is a comment
         with :param inside */
      SELECT * FROM users WHERE id = :id
      """

      {:ok, tokens, _} = NimbleParsecImpl.tokenize(sql)

      assert tokens == [
               {:fragment, "\nSELECT * FROM users WHERE id = "},
               {:named_param, :id},
               {:fragment, "\n"}
             ]
    end

    test "MySQLスタイルコメント" do
      sql = """
      # MySQL comment with :param
      SELECT * FROM users WHERE id = :id
      """

      {:ok, tokens, _} = NimbleParsecImpl.tokenize(sql)

      assert tokens == [
               {:fragment, "SELECT * FROM users WHERE id = "},
               {:named_param, :id},
               {:fragment, "\n"}
             ]
    end

    test "インラインコメント" do
      sql = "SELECT * FROM users WHERE id = :id -- :comment_param"
      {:ok, tokens, _} = NimbleParsecImpl.tokenize(sql)

      assert tokens == [
               {:fragment, "SELECT * FROM users WHERE id = "},
               {:named_param, :id},
               {:fragment, " "}
             ]
    end
  end

  describe "文字列リテラル処理" do
    test "単一引用符内のパラメータ" do
      sql = "SELECT * FROM users WHERE comment = ':not_param' AND id = :id"
      {:ok, tokens, _} = NimbleParsecImpl.tokenize(sql)

      assert tokens == [
               {:fragment, "SELECT * FROM users WHERE comment = ':not_param' AND id = "},
               {:named_param, :id}
             ]
    end

    test "二重引用符内のパラメータ" do
      sql = ~s|SELECT * FROM "table:with:colons" WHERE id = :id|
      {:ok, tokens, _} = NimbleParsecImpl.tokenize(sql)

      assert tokens == [
               {:fragment, ~s|SELECT * FROM "table:with:colons" WHERE id = |},
               {:named_param, :id}
             ]
    end

    test "エスケープされた引用符" do
      sql = "SELECT * FROM users WHERE name = 'O\\'Brien' AND id = :id"
      {:ok, tokens, _} = NimbleParsecImpl.tokenize(sql)

      assert tokens == [
               {:fragment, "SELECT * FROM users WHERE name = 'O\\'Brien' AND id = "},
               {:named_param, :id}
             ]
    end
  end

  describe "特殊なケース" do
    test ":: キャスト演算子" do
      sql = "SELECT id::text FROM users WHERE id = :id"
      {:ok, tokens, _} = NimbleParsecImpl.tokenize(sql)

      assert tokens == [
               {:fragment, "SELECT id::text FROM users WHERE id = "},
               {:named_param, :id}
             ]
    end

    test "URL内のコロン" do
      sql = "INSERT INTO logs (url) VALUES ('https://example.com')"
      {:ok, tokens, _} = NimbleParsecImpl.tokenize(sql)

      assert tokens == [
               {:fragment, "INSERT INTO logs (url) VALUES ('https://example.com')"}
             ]
    end

    test "複雑な組み合わせ" do
      sql = """
      -- Header: :comment_param
      SELECT 
        u.id::text,
        ':literal' as label,
        /* :block_param */ u.name
      FROM users u
      WHERE u.email = :email -- :inline_comment
        AND u.status = ':active'
      """

      {:ok, tokens, _} = NimbleParsecImpl.tokenize(sql)

      # コメント内のパラメータは無視され、実際のパラメータのみ認識
      param_tokens = Enum.filter(tokens, &match?({:named_param, _}, &1))
      assert param_tokens == [{:named_param, :email}]
    end
  end

  describe "エラーケース" do
    test "不正なパラメータ名" do
      sql = "SELECT * FROM users WHERE id = :123invalid"
      {:ok, tokens, _} = NimbleParsecImpl.tokenize(sql)

      # :123 はパラメータとして認識されない
      assert Enum.all?(tokens, &match?({:fragment, _}, &1))
    end
  end

  describe "既存トークナイザーとの互換性" do
    test "デフォルトトークナイザーとの比較" do
      sqls = [
        "SELECT * FROM users",
        "SELECT * FROM users WHERE id = :id",
        "SELECT * FROM users WHERE name = :name AND age > :age"
      ]

      for sql <- sqls do
        {:ok, default_tokens, _} = Yesql.Tokenizer.Default.tokenize(sql)
        {:ok, nimble_tokens, _} = NimbleParsecImpl.tokenize(sql)

        assert default_tokens == nimble_tokens,
               "SQL: #{sql}\nDefault: #{inspect(default_tokens)}\nNimble: #{inspect(nimble_tokens)}"
      end
    end
  end
end
