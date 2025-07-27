defmodule Yesql.DriverFactoryTest do
  use ExUnit.Case

  describe "create/1" do
    test "Postgrexドライバーの作成" do
      assert {:ok, driver} = Yesql.DriverFactory.create(:postgrex)
      assert %Yesql.Driver.Postgrex{} = driver
    end

    test "Ectoドライバーの作成" do
      assert {:ok, driver} = Yesql.DriverFactory.create(:ecto)
      assert %Yesql.Driver.Ecto{} = driver
    end

    @tag :duckdb
    test "DuckDBドライバーの作成" do
      if System.get_env("DUCKDB_TEST") == "true" do
        assert {:ok, driver} = Yesql.DriverFactory.create(:duckdb)
        assert %Yesql.Driver.DuckDB{} = driver
      else
        {:ok, skip: true}
      end
    end

    test "不明なドライバー" do
      assert {:error, :unknown_driver} = Yesql.DriverFactory.create(:unknown_driver)
    end
  end

  describe "available_drivers/0" do
    test "利用可能なドライバーのリストを返す" do
      drivers = Yesql.DriverFactory.available_drivers()
      assert :postgrex in drivers
      assert :ecto in drivers

      # DuckDBはDUCKDB_TEST環境変数に依存
      if System.get_env("DUCKDB_TEST") == "true" do
        assert :duckdb in drivers
      end
    end
  end
end
