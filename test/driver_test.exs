defmodule Yesql.DriverTest do
  use ExUnit.Case
  import TestHelper

  setup_all do
    case System.get_env("DUCKDB_TEST") do
      "true" ->
        # DuckDBテスト環境では、PostgreSQL接続は不要
        :ok

      _ ->
        # 通常のテスト環境では、PostgreSQL接続を作成
        context = %{module: __MODULE__}

        case new_postgrex_connection(context) do
          {:ok, context_with_conn} ->
            create_cats_postgres_table(context_with_conn)
            {:ok, context_with_conn}

          :skip ->
            {:ok, skip: true}

          {:error, _} ->
            {:ok, skip: true}
        end
    end
  end

  setup context do
    if Map.has_key?(context, :postgrex) do
      truncate_postgres_cats(context)
    end

    :ok
  end

  describe "Postgrexドライバー" do
    @describetag :postgres
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
    @describetag :skip_on_ci
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
      sql = "INSERT INTO test_table (id, value) VALUES ($1, $2)"

      assert {:ok, result} = Yesql.Driver.execute(driver, conn, sql, [1, "test"])
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
      insert_sql = "INSERT INTO test_table (id, value) VALUES ($1, $2)"
      {:ok, _} = Duckdbex.query(conn, insert_sql, [42, "answer"])

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
