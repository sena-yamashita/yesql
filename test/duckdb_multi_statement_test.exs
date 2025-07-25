defmodule DuckDBMultiStatementTest do
  use ExUnit.Case
  
  setup do
    {:ok, db} = Duckdbex.open(":memory:")
    {:ok, conn} = Duckdbex.connection(db)
    driver = %Yesql.Driver.DuckDB{}
    
    # テスト用CSVファイルを作成
    csv_path = "/tmp/test_multi_stmt.csv"
    File.write!(csv_path, """
    id,name,value
    1,Alice,100
    2,Bob,200
    3,Charlie,300
    """)
    
    on_exit(fn ->
      File.rm(csv_path)
    end)
    
    {:ok, conn: conn, driver: driver, csv_path: csv_path}
  end
  
  describe "複数ステートメントのサポート" do
    test "CREATE TABLE + INSERTの複数ステートメント", %{conn: conn, driver: driver, csv_path: csv_path} do
      sql = """
      CREATE TABLE IF NOT EXISTS test_import AS 
      SELECT * FROM read_csv_auto($1) WHERE 1=0;
      
      INSERT INTO test_import 
      SELECT * FROM read_csv_auto($1);
      """
      
      # 実行
      assert {:ok, result} = Yesql.Driver.execute(driver, conn, sql, [csv_path])
      
      # 結果確認
      {:ok, count_result} = Duckdbex.query(conn, "SELECT COUNT(*) as cnt FROM test_import", [])
      rows = Duckdbex.fetch_all(count_result)
      assert [[3]] = rows
    end
    
    test "名前付きパラメータでの複数ステートメント", %{conn: conn, driver: driver, csv_path: csv_path} do
      # Yesqlのトークナイザーを通す
      sql_with_named = """
      CREATE TABLE IF NOT EXISTS :table_name AS 
      SELECT * FROM read_csv_auto(:file_path) WHERE 1=0;
      
      INSERT INTO :table_name 
      SELECT * FROM read_csv_auto(:file_path);
      """
      
      # パラメータ変換
      {converted_sql, param_mapping} = Yesql.Driver.convert_params(driver, sql_with_named, %{})
      
      # パラメータをマッピング
      params = %{table_name: "test_table2", file_path: csv_path}
      ordered_params = Enum.map(param_mapping, &params[&1])
      
      # 実行
      assert {:ok, _result} = Yesql.Driver.execute(driver, conn, converted_sql, ordered_params)
      
      # 結果確認
      {:ok, count_result} = Duckdbex.query(conn, "SELECT COUNT(*) FROM test_table2", [])
      rows = Duckdbex.fetch_all(count_result)
      assert [[3]] = rows
    end
    
    test "トランザクション処理を含む複数ステートメント", %{conn: conn, driver: driver} do
      sql = """
      BEGIN TRANSACTION;
      CREATE TABLE test_tx (id INTEGER, name VARCHAR);
      INSERT INTO test_tx VALUES (1, 'Alice');
      INSERT INTO test_tx VALUES (2, 'Bob');
      COMMIT;
      """
      
      # 実行
      assert {:ok, _result} = Yesql.Driver.execute(driver, conn, sql, [])
      
      # 結果確認
      {:ok, result} = Duckdbex.query(conn, "SELECT * FROM test_tx ORDER BY id", [])
      rows = Duckdbex.fetch_all(result)
      assert [[1, "Alice"], [2, "Bob"]] = rows
    end
    
    test "エラー処理：途中でエラーが発生する場合", %{conn: conn, driver: driver} do
      sql = """
      CREATE TABLE test_error (id INTEGER);
      INSERT INTO test_error VALUES (1);
      INSERT INTO nonexistent_table VALUES (2);
      INSERT INTO test_error VALUES (3);
      """
      
      # エラーが返されることを確認
      assert {:error, error} = Yesql.Driver.execute(driver, conn, sql, [])
      assert is_binary(error)
      
      # 最初のステートメントは実行されたことを確認
      {:ok, result} = Duckdbex.query(conn, "SELECT * FROM test_error", [])
      rows = Duckdbex.fetch_all(result)
      assert [[1]] = rows
    end
    
    test "空のステートメントや余分なセミコロンの処理", %{conn: conn, driver: driver} do
      sql = """
      CREATE TABLE test_empty (id INTEGER);;
      
      ;
      INSERT INTO test_empty VALUES (1);
      ;
      """
      
      # 正常に実行されることを確認
      assert {:ok, _result} = Yesql.Driver.execute(driver, conn, sql, [])
      
      # 結果確認
      {:ok, result} = Duckdbex.query(conn, "SELECT * FROM test_empty", [])
      rows = Duckdbex.fetch_all(result)
      assert [[1]] = rows
    end
  end
  
  describe "単一ステートメントとの互換性" do
    test "単一ステートメントは従来通り動作", %{conn: conn, driver: driver} do
      sql = "SELECT 42 as answer"
      
      # 実行
      assert {:ok, result} = Yesql.Driver.execute(driver, conn, sql, [])
      assert %{rows: [[42]], columns: _} = result
    end
    
    test "末尾セミコロン付き単一ステートメント", %{conn: conn, driver: driver} do
      sql = "SELECT 42 as answer;"
      
      # 実行
      assert {:ok, result} = Yesql.Driver.execute(driver, conn, sql, [])
      assert %{rows: [[42]], columns: _} = result
    end
  end
end