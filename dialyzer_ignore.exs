[
  # Mixタスクファイルは一括で無視（本番環境では使用されない）
  {~r/lib\/mix\/tasks\/.+\.ex$/, :_},
  
  # Leex生成ファイルの警告を無視
  {~r/\/leexinc\.hrl$/, :pattern_match},
  {"src/Elixir.Yesql.Tokenizer.erl", :_},
  
  # DateTimeのパターンマッチ（Elixirバージョン間の違い）
  {"lib/yesql/driver/tds.ex", :pattern_match},
  {"lib/yesql/driver/mysql.ex", :pattern_match},
  {"lib/yesql/driver/mssql.ex", :pattern_match},
  {"lib/yesql/driver/duckdb.ex", :pattern_match},
  
  # DuckDBドライバーの特殊なパターン
  {"lib/yesql/driver/duckdb.ex", :unmatched_return},
  
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
  
  # Mix関数（開発環境でのみ使用）
  {"lib/yesql/test_setup.ex", :unknown_function, ["Mix.env/0", "Mix.env/1", "Mix.Project.build_path/0"]},
  {"lib/yesql/ecto_test_helper.ex", :unknown_function, ["Mix.env/0", "Mix.env/1", "Mix.shell/0"]},
  
  # Decimalライブラリ（オプショナル）
  {"lib/yesql/driver/tds.ex", :unknown_function, ["Decimal.to_string/1"]},
  
  # パターンマッチのカバレッジ警告（ドライバー固有）
  {"lib/yesql/driver_factory.ex", :pattern_match_cov},
  {"lib/yesql/stream.ex", :pattern_match_cov},
  
  # 無名関数の例外（エラーハンドリング - ストリーミング）
  {"lib/yesql/stream.ex", :only_terminates_with_explicit_exception},
  {"lib/yesql/driver/postgrex.ex", :only_terminates_with_explicit_exception},
  {"lib/yesql/driver/mysql.ex", :only_terminates_with_explicit_exception},
  {"lib/yesql/driver/mssql.ex", :only_terminates_with_explicit_exception},
  {"lib/yesql/driver/sqlite.ex", :only_terminates_with_explicit_exception},
  {"lib/yesql/driver/duckdb.ex", :only_terminates_with_explicit_exception}
]