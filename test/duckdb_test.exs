defmodule DuckDBTest do
  use ExUnit.Case

  # DuckDBが利用可能な場合のみテストを実行
  @moduletag :skip_on_ci

  defmodule QueryDuckDB do
    use Yesql, driver: :duckdb

    Yesql.defquery("test/sql/duckdb/select_older_ducks.sql")
    Yesql.defquery("test/sql/duckdb/insert_duck.sql")
    Yesql.defquery("test/sql/duckdb/analytics_query.sql")
  end

  setup_all do
    case System.get_env("DUCKDB_TEST") do
      "true" ->
        {:ok, db} = Duckdbex.open(":memory:")
        {:ok, conn} = Duckdbex.connection(db)

        # テーブル作成
        create_sql = """
        CREATE TABLE ducks (
          age INTEGER NOT NULL,
          name VARCHAR
        )
        """

        {:ok, _} = Duckdbex.query(conn, create_sql, [])

        # 分析用テーブル作成
        analytics_sql = """
        CREATE TABLE sales (
          date DATE,
          product VARCHAR,
          amount DECIMAL(10,2),
          quantity INTEGER
        )
        """

        {:ok, _} = Duckdbex.query(conn, analytics_sql, [])

        # core_functionsエクステンションをロード（SUM等の集計関数用）
        {:ok, _} = Duckdbex.query(conn, "INSTALL core_functions", [])
        {:ok, _} = Duckdbex.query(conn, "LOAD core_functions", [])

        {:ok, conn: conn, db: db}

      _ ->
        {:ok, skip: true}
    end
  end

  setup context do
    case context do
      %{conn: conn} when is_reference(conn) ->
        # 各テスト前にテーブルをクリア
        {:ok, _} = Duckdbex.query(conn, "DELETE FROM ducks", [])
        {:ok, _} = Duckdbex.query(conn, "DELETE FROM sales", [])
        :ok

      _ ->
        :ok
    end
  end

  describe "DuckDB driver" do
    @describetag :duckdb
    @describetag :skip_on_ci
    test "基本的なinsertとselect", %{conn: conn} do
      # データ挿入
      assert QueryDuckDB.insert_duck(conn, age: 5, name: "Donald") == {:ok, []}
      assert QueryDuckDB.insert_duck(conn, age: 10, name: "Daisy") == {:ok, []}
      assert QueryDuckDB.insert_duck(conn, age: 3, name: "Huey") == {:ok, []}

      # 年齢でフィルタリング
      assert {:ok, result} = QueryDuckDB.select_older_ducks(conn, age: 4)
      assert length(result) == 2
      assert Enum.find(result, &(&1.name == "Donald"))
      assert Enum.find(result, &(&1.name == "Daisy"))
    end

    @tag :duckdb
    test "パラメータ変換が正しく動作する", %{conn: conn} do
      # 複数のパラメータを使用
      assert QueryDuckDB.insert_duck(conn, age: 7, name: "Scrooge") == {:ok, []}

      # 名前付きパラメータが正しく$1, $2形式に変換されることを確認
      assert {:ok, result} = QueryDuckDB.select_older_ducks(conn, age: 6)
      assert length(result) == 1
      assert hd(result).name == "Scrooge"
    end

    @tag :duckdb
    test "分析クエリの実行", %{conn: conn} do
      # サンプルデータ挿入
      sales_data = [
        {~D[2024-01-01], "Product A", 100.50, 5},
        {~D[2024-01-01], "Product B", 200.00, 3},
        {~D[2024-01-02], "Product A", 150.75, 7},
        {~D[2024-01-02], "Product B", 175.25, 2}
      ]

      for {date, product, amount, quantity} <- sales_data do
        sql = "INSERT INTO sales (date, product, amount, quantity) VALUES ($1, $2, $3, $4)"
        # DuckDBexはDate型を直接サポートしないため、文字列に変換
        {:ok, _} = Duckdbex.query(conn, sql, [Date.to_iso8601(date), product, amount, quantity])
      end

      # 分析クエリ実行
      assert {:ok, result} =
               QueryDuckDB.analytics_query(conn,
                 start_date: ~D[2024-01-01],
                 end_date: ~D[2024-01-02]
               )

      assert length(result) == 2

      # 結果の検証
      product_a = Enum.find(result, &(&1.product == "Product A"))
      # DuckDBはDecimalを{{分子, 符号}, 基数, 精度}の形式で返す
      assert product_a.total_amount == {{25125, 0}, 38, 2}
      # SUMの結果も特殊な形式で返される
      assert product_a.total_quantity == {0, 12}
    end

    @tag :duckdb
    test "エラーハンドリング", %{conn: conn} do
      # 無効なカラム名でエラー
      invalid_sql = "INSERT INTO ducks (invalid_column) VALUES ($1)"
      assert {:error, _} = Duckdbex.query(conn, invalid_sql, [123])
    end
  end

  describe "結果セット変換" do
    @tag :duckdb
    @tag :skip_on_ci
    test "DuckDBの結果が正しく変換される", %{conn: conn} do
      # データ挿入
      QueryDuckDB.insert_duck(conn, age: 25, name: "Ludwig")

      # 結果取得
      assert {:ok, [duck]} = QueryDuckDB.select_older_ducks(conn, age: 20)

      # 結果がマップ形式であることを確認
      assert is_map(duck)
      assert duck.age == 25
      assert duck.name == "Ludwig"
    end

    @tag :duckdb
    test "NULL値の処理", %{conn: conn} do
      # nameをNULLで挿入
      sql = "INSERT INTO ducks (age, name) VALUES ($1, NULL)"
      {:ok, _} = Duckdbex.query(conn, sql, [15])

      # 結果取得
      assert {:ok, [duck]} = QueryDuckDB.select_older_ducks(conn, age: 10)
      assert duck.age == 15
      assert duck.name == nil
    end
  end
end
