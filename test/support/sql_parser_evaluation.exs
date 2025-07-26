# SQL パーサーライブラリの評価スクリプト
# 
# このスクリプトは elixir-dbvisor/sql ライブラリが
# YesQL のトークナイザーとして適しているか評価します。

defmodule SqlParserEvaluation do
  @moduledoc """
  elixir-dbvisor/sql ライブラリの評価
  
  評価項目：
  1. コメント処理（--, /*, #）
  2. 文字列リテラル処理
  3. パラメータ認識
  4. YesQL形式（:param）のサポート可能性
  """
  
  def evaluate do
    IO.puts("=== SQL Parser Library Evaluation ===\n")
    
    test_cases = [
      # 基本的なパラメータ
      {"基本パラメータ", "SELECT * FROM users WHERE id = {{id}}"},
      
      # コメント内のパラメータ
      {"単一行コメント", "-- This uses {{comment_param}}\nSELECT * FROM users WHERE id = {{id}}"},
      {"複数行コメント", "/* {{block_param}} */\nSELECT * FROM users WHERE id = {{id}}"},
      {"MySQLコメント", "# {{mysql_param}}\nSELECT * FROM users WHERE id = {{id}}"},
      
      # 文字列リテラル内のパラメータ
      {"単一引用符", "SELECT * FROM users WHERE comment = '{{not_param}}' AND id = {{id}}"},
      {"二重引用符", ~s|SELECT * FROM "table_{{name}}" WHERE id = {{id}}|},
      
      # 複雑なケース
      {"混合", """
      -- Query for {{comment_param}}
      SELECT * FROM users
      /* {{block_param}} */
      WHERE status = '{{string_param}}'
        AND id = {{id}}
      """}
    ]
    
    Enum.each(test_cases, &test_case/1)
    
    IO.puts("\n=== YesQL形式への変換可能性 ===")
    test_yesql_compatibility()
  end
  
  defp test_case({name, sql}) do
    IO.puts("\nテスト: #{name}")
    IO.puts("SQL: #{inspect(sql)}")
    
    try do
      # ライブラリが存在しないため、シミュレーション
      # 実際には: sql |> SQL.sigil_SQL([], []) |> SQL.to_sql()
      IO.puts("→ ライブラリが必要です")
    catch
      kind, error ->
        IO.puts("エラー: #{kind} - #{inspect(error)}")
    end
  end
  
  defp test_yesql_compatibility do
    IO.puts("""
    
    YesQL形式（:param）からの変換方法：
    
    1. プリプロセッサアプローチ
       :param → {{param}} に変換してから SQL パーサーを使用
       
    2. カスタムレクサー拡張
       ライブラリのレクサーを拡張して :param 形式をサポート
       
    3. ポストプロセッサアプローチ
       SQL パーサーの結果を変換
    """)
  end
end

# 実行
# SqlParserEvaluation.evaluate()