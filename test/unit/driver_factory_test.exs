defmodule Yesql.Unit.DriverFactoryTest do
  use ExUnit.Case, async: true

  @moduletag :unit

  describe "DriverFactory.create/1" do
    test "Postgrexドライバーの作成" do
      assert {:ok, driver} = Yesql.DriverFactory.create(:postgrex)
      assert driver.__struct__ == Yesql.Driver.Postgrex
    end

    test "Ectoドライバーの作成" do
      assert {:ok, driver} = Yesql.DriverFactory.create(:ecto)
      assert driver.__struct__ == Yesql.Driver.Ecto
    end

    test "DuckDBドライバーの作成" do
      assert {:ok, driver} = Yesql.DriverFactory.create(:duckdb)
      assert driver.__struct__ == Yesql.Driver.DuckDB
    end

    test "MySQLドライバーの作成" do
      assert {:ok, driver} = Yesql.DriverFactory.create(:mysql)
      assert driver.__struct__ == Yesql.Driver.MySQL
    end

    test "MSSQLドライバーの作成" do
      assert {:ok, driver} = Yesql.DriverFactory.create(:mssql)
      assert driver.__struct__ == Yesql.Driver.MSSQL
    end

    test "Oracleドライバーの作成" do
      assert {:ok, driver} = Yesql.DriverFactory.create(:oracle)
      assert driver.__struct__ == Yesql.Driver.Oracle
    end

    test "SQLiteドライバーの作成" do
      assert {:ok, driver} = Yesql.DriverFactory.create(:sqlite)
      assert driver.__struct__ == Yesql.Driver.SQLite
    end

    test "未知のドライバー" do
      assert {:error, :unknown_driver} = Yesql.DriverFactory.create(:unknown)
    end

    test "モジュール名からアトムへの変換" do
      assert {:ok, driver} = Yesql.DriverFactory.create(Postgrex)
      assert driver.__struct__ == Yesql.Driver.Postgrex
    end
  end

  describe "パラメータ変換の確認" do
    test "Postgrexは$1形式" do
      {:ok, driver} = Yesql.DriverFactory.create(:postgrex)
      {sql, params} = Yesql.Driver.convert_params(driver, "SELECT * WHERE id = :id", [])
      assert sql == "SELECT * WHERE id = $1"
      assert params == [:id]
    end

    test "MySQLは?形式" do
      {:ok, driver} = Yesql.DriverFactory.create(:mysql)
      {sql, params} = Yesql.Driver.convert_params(driver, "SELECT * WHERE id = :id", [])
      assert sql == "SELECT * WHERE id = ?"
      assert params == [:id]
    end

    test "複数パラメータの変換（PostgreSQL）" do
      {:ok, driver} = Yesql.DriverFactory.create(:postgrex)
      sql = "SELECT * WHERE name = :name AND age > :age AND city = :name"
      {converted_sql, params} = Yesql.Driver.convert_params(driver, sql, [])
      assert converted_sql == "SELECT * WHERE name = $1 AND age > $2 AND city = $1"
      assert params == [:name, :age]
    end

    test "複数パラメータの変換（MySQL）" do
      {:ok, driver} = Yesql.DriverFactory.create(:mysql)
      sql = "SELECT * WHERE name = :name AND age > :age"
      {converted_sql, params} = Yesql.Driver.convert_params(driver, sql, [])
      assert converted_sql == "SELECT * WHERE name = ? AND age > ?"
      assert params == [:name, :age]
    end
  end
end
