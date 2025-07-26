defmodule RealWorldCastTest do
  use ExUnit.Case
  import TestHelper

  @moduletag :real_world_cast

  # 実際のユースケースに基づいたテスト

  describe "PostgreSQL実使用例" do
    defmodule PGRealWorldQueries do
      use Yesql, driver: Postgrex
      
      # JSONB検索クエリ
      defquery "test/sql/real_world/pg_jsonb_search.sql"
      
      # 時系列データクエリ
      defquery "test/sql/real_world/pg_timeseries.sql"
      
      # 配列操作クエリ
      defquery "test/sql/real_world/pg_array_ops.sql"
    end

    setup do
      case TestHelper.new_postgrex_connection(%{module: __MODULE__}) do
        {:ok, ctx} ->
          create_pg_real_world_tables(ctx)
          ctx
        _ -> 
          :skip
      end
    end

    @tag :postgres
    test "JSONB検索でのキャスト", %{postgrex: conn} do
      # テストデータ
      user_data = %{
        "name" => "Alice",
        "age" => 30,
        "tags" => ["developer", "elixir"],
        "profile" => %{
          "city" => "Tokyo",
          "country" => "Japan"
        }
      }

      {:ok, _} = Postgrex.query(conn, 
        "INSERT INTO users (data) VALUES ($1::jsonb)", 
        [user_data]
      )

      # Yesqlクエリの実行
      {:ok, results} = PGRealWorldQueries.search_users_by_jsonb(conn,
        min_age: 25,
        tags: ["elixir"],
        city: "Tokyo"
      )

      assert length(results) == 1
      assert hd(results).data["name"] == "Alice"
    end

    @tag :postgres
    test "時系列データでのキャスト", %{postgrex: conn} do
      # 時系列データの挿入
      now = DateTime.utc_now()
      
      Enum.each(0..23, fn hours_ago ->
        timestamp = DateTime.add(now, -hours_ago * 3600, :second)
        value = :rand.uniform(100)
        
        {:ok, _} = Postgrex.query(conn, """
          INSERT INTO timeseries (timestamp, value, metadata)
          VALUES ($1::timestamptz, $2::numeric, $3::jsonb)
        """, [timestamp, value, %{"sensor" => "temp_01"}])
      end)

      # 集計クエリ
      {:ok, results} = PGRealWorldQueries.aggregate_timeseries(conn,
        start_time: DateTime.add(now, -24 * 3600, :second),
        end_time: now,
        interval: "1 hour",
        sensor: "temp_01"
      )

      assert length(results) > 0
      assert hd(results).hour != nil
      assert hd(results).avg_value != nil
    end

    @tag :postgres  
    test "配列操作でのキャスト", %{postgrex: conn} do
      # 配列データの挿入
      {:ok, _} = Postgrex.query(conn, """
        INSERT INTO products (name, tags, prices, features)
        VALUES 
          ($1, $2::text[], $3::numeric[], $4::jsonb),
          ($5, $6::text[], $7::numeric[], $8::jsonb)
      """, [
        "Product A", ["electronics", "mobile"], [99.99, 89.99], %{"color" => "black"},
        "Product B", ["electronics", "laptop"], [999.99, 899.99], %{"color" => "silver"}
      ])

      # 配列検索
      {:ok, results} = PGRealWorldQueries.search_products_by_arrays(conn,
        required_tags: ["electronics"],
        max_price: Decimal.new("1000"),
        excluded_tags: ["desktop"]
      )

      assert length(results) == 2
    end
  end

  describe "DuckDB実使用例" do
    defmodule DuckDBRealWorldQueries do
      use Yesql, driver: :duckdb
      
      # 分析クエリ
      defquery "test/sql/real_world/duckdb_analytics.sql"
    end

    setup do
      case TestHelper.new_duckdb_connection(%{}) do
        {:ok, ctx} ->
          create_duckdb_analytics_table(ctx)
          ctx
        _ -> 
          :skip
      end
    end

    @tag :duckdb
    test "分析クエリでのキャスト", %{duckdb: conn} do
      # 分析用データの作成
      Enum.each(1..1000, fn i ->
        date = Date.add(~D[2024-01-01], rem(i, 365))
        category = Enum.random(["A", "B", "C"])
        amount = :rand.uniform(1000)
        
        Duckdbex.query(conn, """
          INSERT INTO sales_data (date, category, amount)
          VALUES ($1::DATE, $2::VARCHAR, $3::DECIMAL)
        """, [date, category, amount])
      end)

      # 分析クエリの実行
      {:ok, results} = DuckDBRealWorldQueries.analyze_sales(conn,
        start_date: ~D[2024-01-01],
        end_date: ~D[2024-12-31],
        min_amount: Decimal.new("100")
      )

      assert length(results) > 0
    end
  end

  # ヘルパー関数

  defp create_pg_real_world_tables(%{postgrex: conn}) do
    # JSONB検索用テーブル
    {:ok, _} = Postgrex.query(conn, """
      CREATE TABLE IF NOT EXISTS users (
        id SERIAL PRIMARY KEY,
        data JSONB NOT NULL,
        created_at TIMESTAMPTZ DEFAULT NOW()
      )
    """, [])

    # 時系列データテーブル
    {:ok, _} = Postgrex.query(conn, """
      CREATE TABLE IF NOT EXISTS timeseries (
        timestamp TIMESTAMPTZ NOT NULL,
        value NUMERIC NOT NULL,
        metadata JSONB,
        PRIMARY KEY (timestamp, metadata)
      )
    """, [])

    # 配列操作テーブル
    {:ok, _} = Postgrex.query(conn, """
      CREATE TABLE IF NOT EXISTS products (
        id SERIAL PRIMARY KEY,
        name TEXT NOT NULL,
        tags TEXT[],
        prices NUMERIC[],
        features JSONB
      )
    """, [])

    # データクリーンアップ
    {:ok, _} = Postgrex.query(conn, "TRUNCATE users, timeseries, products", [])
    
    :ok
  end

  defp create_duckdb_analytics_table(%{duckdb: conn}) do
    Duckdbex.query(conn, """
      CREATE TABLE IF NOT EXISTS sales_data (
        date DATE,
        category VARCHAR,
        amount DECIMAL(10,2)
      )
    """, [])
    
    Duckdbex.query(conn, "DELETE FROM sales_data", [])
    :ok
  end
end