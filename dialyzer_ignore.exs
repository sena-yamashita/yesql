[
  # オプショナルな依存関係に関する警告をすべて無視
  # これらの関数は実行時に存在チェックされる
  {~r/lib\/yesql\/.+\.ex$/, :unknown_function},
  
  # Leex生成ファイルの警告を無視
  {~r/\/leexinc\.hrl$/, :pattern_match},
  {"src/Elixir.Yesql.Tokenizer.erl", :_},
  
  # Mix環境関連（本番環境では使用されない）
  {"lib/yesql/debug.ex", :unknown_function},
  {"lib/mix/tasks", :unknown_function},
  {~r/lib\/mix\/tasks\/.+\.ex$/, :unknown_function},
  
  # DuckDBドライバーの特殊なパターン
  {"lib/yesql/driver/duckdb.ex", :unmatched_return},
  
  # DateTimeのパターンマッチ（Elixirバージョン間の違い）
  {~r/lib\/yesql\/driver\/.+\.ex$/, :pattern_match},
  
  # ストリーミング実装のパターンマッチ
  {"lib/yesql/stream.ex", :guard_fail},
  {"lib/yesql/stream.ex", :pattern_match_cov},
  
  # トランザクションのrollback（正常な動作）
  {"lib/yesql/transaction.ex", :no_return},
  
  # 式の型の不一致（エラーハンドリング）
  {"lib/yesql.ex", :expr_mismatch},
  {~r/lib\/yesql\/driver\/.+\.ex$/, :expr_mismatch},
  
  # Mix.Taskビヘイビアの警告
  {~r/lib\/mix\/tasks\/.+\.ex$/, :callback_info_missing},
  
  # テスト環境関連の警告
  {"lib/yesql/test_setup.ex", :unknown_function},
  {"lib/yesql/ecto_test_helper.ex", :unknown_function},
  
  # Decimalライブラリ（オプショナル）
  {"lib/yesql/driver/tds.ex", :unknown_function}
]