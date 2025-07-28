[
  # Mixタスクファイルは一括で無視（本番環境では使用されない）
  {~r/lib\/mix\/tasks\/.+\.ex$/, :_},
  
  # Leex生成ファイルの警告を無視
  {~r/\/leexinc\.hrl$/, :pattern_match},
  {"src/Elixir.Yesql.Tokenizer.erl", :_},
  
  # DuckDBドライバーの特殊なパターン
  {"lib/yesql/driver/duckdb.ex", :unmatched_return},
  
  # DateTimeのパターンマッチ（Elixirバージョン間の違い）
  {"lib/yesql/driver/tds.ex", :pattern_match},
  {"lib/yesql/driver/mysql.ex", :pattern_match},
  {"lib/yesql/driver/mssql.ex", :pattern_match},
  {"lib/yesql/driver/duckdb.ex", :pattern_match},
  
  # ストリーミング実装のパターンマッチ
  {"lib/yesql/stream.ex", :guard_fail},
  {"lib/yesql/stream.ex", :pattern_match_cov},
  
  # トランザクションのrollback（正常な動作）
  {"lib/yesql/transaction.ex", :no_return},
  
  # 式の型の不一致（エラーハンドリング）
  {"lib/yesql.ex", :expr_mismatch},
  {"lib/yesql/driver/postgrex.ex", :expr_mismatch},
  {"lib/yesql/driver/ecto.ex", :expr_mismatch},
  {"lib/yesql/driver/mysql.ex", :expr_mismatch},
  {"lib/yesql/driver/mssql.ex", :expr_mismatch},
  {"lib/yesql/driver/sqlite.ex", :expr_mismatch},
  {"lib/yesql/driver/duckdb.ex", :expr_mismatch},
  {"lib/yesql/driver/oracle.ex", :expr_mismatch},
  
  # テスト環境関連の警告
  {"lib/yesql/test_setup.ex", :unknown_function},
  {"lib/yesql/ecto_test_helper.ex", :unknown_function},
  
  # Decimalライブラリ（オプショナル）
  {"lib/yesql/driver/tds.ex", :unknown_function},
  
  # 無名関数の例外（エラーハンドリング）
  {~r/lib\/yesql\/.+\.ex$/, :only_terminates_with_explicit_exception},
  
  # パターンマッチのカバレッジ警告
  {~r/lib\/yesql\/.+\.ex$/, :pattern_match_cov}
]