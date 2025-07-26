defmodule Yesql.Unit.TokenizerConfigTest do
  use ExUnit.Case, async: true
  
  @moduletag :unit
  
  alias Yesql.Config
  
  describe "トークナイザー設定" do
    setup do
      # テスト前に設定をリセット
      Config.reset_tokenizer()
      :ok
    end
    
    test "デフォルトトークナイザーが設定される" do
      assert Config.get_tokenizer() == Yesql.Tokenizer.Default
    end
    
    test "トークナイザーを設定できる" do
      # ダミーモジュールを設定
      Config.put_tokenizer(MyApp.CustomTokenizer)
      assert Config.get_tokenizer() == MyApp.CustomTokenizer
    end
    
    test "トークナイザーをリセットできる" do
      Config.put_tokenizer(MyApp.CustomTokenizer)
      Config.reset_tokenizer()
      assert Config.get_tokenizer() == Yesql.Tokenizer.Default
    end
    
    test "with_tokenizerで一時的にトークナイザーを変更できる" do
      # 初期状態を確認
      assert Config.get_tokenizer() == Yesql.Tokenizer.Default
      
      # ブロック内でのみ変更
      result = Config.with_tokenizer(MyApp.TempTokenizer, fn ->
        Config.get_tokenizer()
      end)
      
      assert result == MyApp.TempTokenizer
      # ブロック外では元に戻る
      assert Config.get_tokenizer() == Yesql.Tokenizer.Default
    end
    
    test "with_tokenizerのネスト" do
      Config.put_tokenizer(MyApp.BaseTokenizer)
      
      Config.with_tokenizer(MyApp.OuterTokenizer, fn ->
        assert Config.get_tokenizer() == MyApp.OuterTokenizer
        
        Config.with_tokenizer(MyApp.InnerTokenizer, fn ->
          assert Config.get_tokenizer() == MyApp.InnerTokenizer
        end)
        
        # 外側のトークナイザーに戻る
        assert Config.get_tokenizer() == MyApp.OuterTokenizer
      end)
      
      # 元のトークナイザーに戻る
      assert Config.get_tokenizer() == MyApp.BaseTokenizer
    end
  end
  
  describe "デフォルトトークナイザーの動作" do
    test "既存のトークナイザーをラップする" do
      sql = "SELECT * FROM users WHERE id = :id"
      {:ok, tokens, _} = Yesql.Tokenizer.Default.tokenize(sql)
      
      assert tokens == [
        {:fragment, "SELECT * FROM users WHERE id = "},
        {:named_param, :id}
      ]
    end
    
    test "エラーケースも正しく処理する" do
      # : の後にスペースがあるとエラー
      sql = "SELECT * FROM users WHERE status = : active"
      assert {:error, _, _} = Yesql.Tokenizer.Default.tokenize(sql)
    end
  end
  
  describe "トークナイザーヘルパー" do
    test "設定されたトークナイザーを使用する" do
      sql = "SELECT * FROM users WHERE id = :id"
      {:ok, tokens, _} = Yesql.TokenizerHelper.tokenize(sql)
      
      assert length(tokens) == 2
    end
    
    test "パラメータ抽出と変換" do
      tokens = [
        {:fragment, "SELECT * FROM users WHERE id = "},
        {:named_param, :id},
        {:fragment, " AND name = "},
        {:named_param, :name}
      ]
      
      format_param = fn _param, index -> "$#{index}" end
      {sql, params} = Yesql.TokenizerHelper.extract_and_convert_params(tokens, format_param)
      
      assert sql == "SELECT * FROM users WHERE id = $1 AND name = $2"
      assert params == [:id, :name]
    end
    
    test "重複パラメータの処理" do
      tokens = [
        {:fragment, "WHERE name = "},
        {:named_param, :name},
        {:fragment, " OR alias = "},
        {:named_param, :name}
      ]
      
      format_fn = fn -> "?" end
      {sql, params} = Yesql.TokenizerHelper.extract_params_with_duplicates(tokens, format_fn)
      
      assert sql == "WHERE name = ? OR alias = ?"
      assert params == [:name, :name]
    end
  end
  
  describe "各ドライバーでのトークナイザー使用" do
    test "PostgreSQLドライバー" do
      {:ok, driver} = Yesql.DriverFactory.create(:postgrex)
      sql = "SELECT * FROM users WHERE id = :id"
      
      {converted_sql, params} = Yesql.Driver.convert_params(driver, sql, [])
      
      assert converted_sql == "SELECT * FROM users WHERE id = $1"
      assert params == [:id]
    end
    
    test "MySQLドライバー" do
      {:ok, driver} = Yesql.DriverFactory.create(:mysql)
      sql = "SELECT * FROM users WHERE name = :name AND alias = :name"
      
      {converted_sql, params} = Yesql.Driver.convert_params(driver, sql, [])
      
      assert converted_sql == "SELECT * FROM users WHERE name = ? AND alias = ?"
      assert params == [:name, :name]
    end
  end
end