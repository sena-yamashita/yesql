defmodule Yesql.DriverTest do
  use ExUnit.Case
  import TestHelper

  setup_all [:new_postgrex_connection, :create_cats_postgres_table]
  setup [:truncate_postgres_cats]

  describe "Postgrexドライバー" do
    test "execute/4の動作", %{postgrex: conn} do
      driver = %Yesql.Driver.Postgrex{}
      sql = "INSERT INTO cats (age, name) VALUES ($1, $2)"
      
      assert {:ok, result} = Yesql.Driver.execute(driver, conn, sql, [5, "Mittens"])
      assert result.command == :insert
      assert result.num_rows == 1
    end

    test "convert_params/3の動作" do
      driver = %Yesql.Driver.Postgrex{}
      sql = "SELECT * FROM cats WHERE age > :age AND name = :name"
      
      {converted_sql, params} = Yesql.Driver.convert_params(driver, sql, [])
      
      assert converted_sql == "SELECT * FROM cats WHERE age > $1 AND name = $2"
      assert params == [:age, :name]
    end

    test "process_result/2の動作", %{postgrex: conn} do
      driver = %Yesql.Driver.Postgrex{}
      
      # データ挿入
      insert_sql = "INSERT INTO cats (age, name) VALUES ($1, $2)"
      {:ok, _} = Postgrex.query(conn, insert_sql, [10, "Felix"])
      
      # データ取得
      select_sql = "SELECT * FROM cats"
      {:ok, result} = Postgrex.query(conn, select_sql, [])
      
      # 結果変換
      assert {:ok, processed} = Yesql.Driver.process_result(driver, {:ok, result})
      assert [%{age: 10, name: "Felix"}] = processed
    end
  end

  describe "Ectoドライバー" do
    test "convert_params/3の動作" do
      driver = %Yesql.Driver.Ecto{}
      sql = "SELECT * FROM users WHERE email = :email"
      
      {converted_sql, params} = Yesql.Driver.convert_params(driver, sql, [])
      
      assert converted_sql == "SELECT * FROM users WHERE email = $1"
      assert params == [:email]
    end

    test "パラメータの重複処理" do
      driver = %Yesql.Driver.Ecto{}
      sql = "SELECT * FROM items WHERE category = :cat AND sub_category = :cat"
      
      {converted_sql, params} = Yesql.Driver.convert_params(driver, sql, [])
      
      # 同じパラメータは同じ番号を使用
      assert converted_sql == "SELECT * FROM items WHERE category = $1 AND sub_category = $1"
      assert params == [:cat]
    end
  end

  describe "DuckDBドライバー" do
    @describetag :duckdb
    setup do
      case System.get_env("DUCKDB_TEST") do
        "true" ->
          {:ok, db} = Duckdbex.open(":memory:")
          {:ok, conn} = Duckdbex.connection(db)
          
          # テーブル作成
          create_sql = """
          CREATE TABLE test_table (
            id INTEGER,
            value VARCHAR
          )
          """
          {:ok, _} = Duckdbex.query(conn, create_sql, [])
          
          {:ok, duckdb: conn, db: db}
        _ ->
          {:ok, skip: true}
      end
    end

    @tag :duckdb
    test "execute/4の動作", %{duckdb: conn} do
      driver = %Yesql.Driver.DuckDB{}
      # DuckDBはパラメータをサポートしないので、値を直接埋め込む
      sql = "INSERT INTO test_table (id, value) VALUES (1, 'test')"
      
      assert {:ok, result} = Yesql.Driver.execute(driver, conn, sql, [])
      # DuckDBのINSERTは影響した行数を返す
      assert result.rows == [[1]]
    end

    @tag :duckdb
    test "convert_params/3の動作" do
      driver = %Yesql.Driver.DuckDB{}
      sql = "SELECT * FROM test_table WHERE id = :id"
      
      {converted_sql, params} = Yesql.Driver.convert_params(driver, sql, [])
      
      assert converted_sql == "SELECT * FROM test_table WHERE id = $1"
      assert params == [:id]
    end

    @tag :duckdb
    test "process_result/2の動作 - キーワードリスト形式", %{duckdb: conn} do
      driver = %Yesql.Driver.DuckDB{}
      
      # データ挿入
      insert_sql = "INSERT INTO test_table (id, value) VALUES (42, 'answer')"
      {:ok, _} = Duckdbex.query(conn, insert_sql, [])
      
      # データ取得
      select_sql = "SELECT id, value FROM test_table"
      {:ok, result_ref} = Duckdbex.query(conn, select_sql, [])
      rows = Duckdbex.fetch_all(result_ref)
      
      # 結果変換（DuckDBexがキーワードリストを返す場合）
      result = %{rows: rows, columns: ["id", "value"]}
      assert {:ok, processed} = Yesql.Driver.process_result(driver, {:ok, result})
      
      # 結果がマップ形式であることを確認
      assert [%{id: 42, value: "answer"}] = processed
    end
  end
end