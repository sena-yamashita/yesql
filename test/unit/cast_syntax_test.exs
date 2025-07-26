defmodule Yesql.Unit.CastSyntaxTest do
  use ExUnit.Case, async: true
  
  @moduletag :unit
  
  describe "各データベースのキャスト構文サポート" do
    test "PostgreSQL :: キャスト構文の変換" do
      {:ok, driver} = Yesql.DriverFactory.create(:postgrex)
      
      # 基本的なキャスト
      {sql, _} = Yesql.Driver.convert_params(driver, "SELECT :id::bigint", [])
      assert sql == "SELECT $1::bigint"
      
      # 複数のキャスト
      {sql, _} = Yesql.Driver.convert_params(driver, 
        "SELECT :name::text, :age::integer, :data::jsonb", [])
      assert sql == "SELECT $1::text, $2::integer, $3::jsonb"
      
      # 配列キャスト
      {sql, _} = Yesql.Driver.convert_params(driver, 
        "SELECT :tags::text[], :numbers::integer[]", [])
      assert sql == "SELECT $1::text[], $2::integer[]"
    end
    
    test "DuckDB :: キャスト構文の変換" do
      {:ok, driver} = Yesql.DriverFactory.create(:duckdb)
      
      # DuckDBも::構文をサポート
      {sql, _} = Yesql.Driver.convert_params(driver, "SELECT :value::VARCHAR", [])
      assert sql == "SELECT $1::VARCHAR"
      
      # 複雑な型
      {sql, _} = Yesql.Driver.convert_params(driver, 
        "SELECT :date::DATE, :time::TIME, :json::JSON", [])
      assert sql == "SELECT $1::DATE, $2::TIME, $3::JSON"
    end
    
    test "MySQL CAST関数形式" do
      {:ok, driver} = Yesql.DriverFactory.create(:mysql)
      
      # MySQLはCAST関数を使用
      {sql, _} = Yesql.Driver.convert_params(driver, 
        "SELECT CAST(:value AS CHAR)", [])
      assert sql == "SELECT CAST(? AS CHAR)"
      
      # 複数のCAST
      {sql, _} = Yesql.Driver.convert_params(driver, 
        "SELECT CAST(:id AS UNSIGNED), CAST(:name AS CHAR(100))", [])
      assert sql == "SELECT CAST(? AS UNSIGNED), CAST(? AS CHAR(100))"
    end
    
    test "SQLite CAST関数形式" do
      {:ok, driver} = Yesql.DriverFactory.create(:sqlite)
      
      # SQLiteもCAST関数を使用
      {sql, _} = Yesql.Driver.convert_params(driver, 
        "SELECT CAST(:value AS INTEGER)", [])
      assert sql == "SELECT CAST(? AS INTEGER)"
    end
    
    test "キャスト構文の混在" do
      {:ok, driver} = Yesql.DriverFactory.create(:postgrex)
      
      # ::とCAST()の混在
      {sql, _} = Yesql.Driver.convert_params(driver, 
        "SELECT :id::bigint, CAST(:name AS text), :data::jsonb", [])
      assert sql == "SELECT $1::bigint, CAST($2 AS text), $3::jsonb"
    end
  end
  
  describe "エッジケース" do
    test "文字列内の :: は変換されない" do
      {:ok, driver} = Yesql.DriverFactory.create(:postgrex)
      
      {sql, _} = Yesql.Driver.convert_params(driver, 
        "SELECT 'value::text' as example, :real::integer", [])
      assert sql == "SELECT 'value::text' as example, $1::integer"
    end
    
    test "コメント内の :param は無視される" do
      {:ok, driver} = Yesql.DriverFactory.create(:postgrex)
      
      sql_with_comment = """
      -- This query uses :id parameter
      SELECT * FROM users WHERE id = :id
      """
      
      {converted_sql, params} = Yesql.Driver.convert_params(driver, sql_with_comment, [])
      assert params == [:id]
      assert converted_sql =~ "$1"
    end
    
    test "複雑なクエリでのキャスト" do
      {:ok, driver} = Yesql.DriverFactory.create(:postgrex)
      
      complex_sql = """
      WITH user_data AS (
        SELECT :user_id::bigint as id, :data::jsonb as info
      )
      SELECT u.*, ud.info
      FROM users u
      JOIN user_data ud ON u.id = ud.id
      WHERE u.tags && :tags::text[]
      """
      
      {converted_sql, params} = Yesql.Driver.convert_params(driver, complex_sql, [])
      assert params == [:user_id, :data, :tags]
      assert converted_sql =~ "$1::bigint"
      assert converted_sql =~ "$2::jsonb"
      assert converted_sql =~ "$3::text[]"
    end
  end
end