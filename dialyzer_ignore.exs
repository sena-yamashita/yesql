[
  # オプショナルな依存関係に関する警告をすべて無視
  # これらの関数は実行時に存在チェックされる
  {~r/lib\/yesql\/.+\.ex$/, :unknown_function},
  
  # Leex生成ファイルの警告を無視
  {~r/\/leexinc\.hrl$/, :pattern_match},
  {"src/Elixir.Yesql.Tokenizer.erl", :_},
  
  # Mix環境関連（本番環境では使用されない）
  {"lib/yesql/debug.ex", :unknown_function},
  
  # DuckDBドライバーの特殊なパターン
  {"lib/yesql/driver/duckdb.ex", :unmatched_return},
  
  # ストリーミング実装のパターンマッチ
  {"lib/yesql/stream.ex", :guard_fail},
  {"lib/yesql/stream.ex", :pattern_match_cov},
  
  # トランザクションのrollback（正常な動作）
  {"lib/yesql/transaction.ex", :no_return}
]