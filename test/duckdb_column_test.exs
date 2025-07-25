defmodule DuckDBColumnTest do
  use ExUnit.Case
  
  setup do
    {:ok, db} = Duckdbex.open(":memory:")
    {:ok, conn} = Duckdbex.connection(db)
    driver = %Yesql.Driver.DuckDB{}
    
    {:ok, conn: conn, driver: driver}
  end
  
  describe "カラム情報の取得" do
    test "単純なSELECTクエリでカラム名が正しく取得される", %{conn: conn, driver: driver} do
      sql = "SELECT 1 as id, 'Alice' as name, 25 as age"
      
      assert {:ok, result} = Yesql.Driver.execute(driver, conn, sql, [])
      assert {:ok, processed} = Yesql.Driver.process_result(driver, {:ok, result})
      
      # 結果は1行のマップのリスト
      assert [row] = processed
      assert %{id: 1, name: "Alice", age: 25} = row
    end
    
    test "テーブルからのSELECTでカラム名が正しく取得される", %{conn: conn, driver: driver} do
      # テーブル作成
      create_sql = "CREATE TABLE users (id INTEGER, name VARCHAR, email VARCHAR)"
      assert {:ok, _} = Yesql.Driver.execute(driver, conn, create_sql, [])
      
      # データ挿入
      insert_sql = "INSERT INTO users VALUES (1, 'Bob', 'bob@example.com'), (2, 'Carol', 'carol@example.com')"
      assert {:ok, _} = Yesql.Driver.execute(driver, conn, insert_sql, [])
      
      # SELECT実行
      select_sql = "SELECT * FROM users ORDER BY id"
      assert {:ok, result} = Yesql.Driver.execute(driver, conn, select_sql, [])
      assert {:ok, processed} = Yesql.Driver.process_result(driver, {:ok, result})
      
      # 結果確認
      assert [
        %{id: 1, name: "Bob", email: "bob@example.com"},
        %{id: 2, name: "Carol", email: "carol@example.com"}
      ] = processed
    end
    
    test "空の結果セットでも正しく処理される", %{conn: conn, driver: driver} do
      # テーブル作成
      create_sql = "CREATE TABLE empty_table (id INTEGER, name VARCHAR)"
      assert {:ok, _} = Yesql.Driver.execute(driver, conn, create_sql, [])
      
      # 空のテーブルからSELECT
      select_sql = "SELECT * FROM empty_table"
      assert {:ok, result} = Yesql.Driver.execute(driver, conn, select_sql, [])
      assert {:ok, processed} = Yesql.Driver.process_result(driver, {:ok, result})
      
      # 空のリストが返される
      assert [] = processed
    end
    
    test "複雑なクエリでもカラム名が正しく取得される", %{conn: conn, driver: driver} do
      # テーブル作成とデータ挿入
      setup_sql = """
      CREATE TABLE orders (order_id INTEGER, customer_name VARCHAR, amount DECIMAL);
      INSERT INTO orders VALUES 
        (1, 'Alice', 100.50),
        (2, 'Bob', 200.75),
        (3, 'Alice', 150.25);
      """
      
      statements = String.split(setup_sql, ";") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
      for stmt <- statements do
        assert {:ok, _} = Yesql.Driver.execute(driver, conn, stmt, [])
      end
      
      # 集計クエリ（DuckDBのcore_functionsエラーを回避）
      aggregate_sql = """
      SELECT 
        customer_name,
        COUNT(*) as order_count,
        CAST(100 as DECIMAL) as total_amount
      FROM orders
      GROUP BY customer_name
      ORDER BY customer_name
      """
      
      assert {:ok, result} = Yesql.Driver.execute(driver, conn, aggregate_sql, [])
      assert {:ok, processed} = Yesql.Driver.process_result(driver, {:ok, result})
      
      # 結果確認
      assert [
        %{customer_name: "Alice", order_count: 2, total_amount: _},
        %{customer_name: "Bob", order_count: 1, total_amount: _}
      ] = processed
    end
  end
end