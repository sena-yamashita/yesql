defmodule PostgreSQLYesqlTest do
  use ExUnit.Case
  import TestHelper

  # Yesqlモジュールの定義（接続が成功した場合のみ定義）
  if match?({:ok, _}, TestHelper.check_postgres_connection()) do
    defmodule PostgresQueries do
      use Yesql, driver: Postgrex

      # JSONB操作
      Yesql.defquery("test/sql/postgresql/jsonb_operations.sql")
      
      # 配列操作
      Yesql.defquery("test/sql/postgresql/array_operations.sql")
      
      # ウィンドウ関数
      Yesql.defquery("test/sql/postgresql/window_functions.sql")
      
      # 再帰CTE
      Yesql.defquery("test/sql/postgresql/cte_recursive.sql")
      
      # 全文検索
      Yesql.defquery("test/sql/postgresql/fulltext_search.sql")
    end
  end

  setup_all do
    case new_postgrex_connection(%{module: __MODULE__}) do
      {:ok, ctx} -> ctx
      _ -> 
        IO.puts("Skipping PostgreSQL Yesql tests - database connection failed")
        :skip
    end
  end

  describe "Yesql PostgreSQL JSONB操作" do
    setup [:create_jsonb_test_table]

    test "JSONBタグ検索", %{postgrex: conn} do
      # テストデータの挿入
      {:ok, _} = Postgrex.query(conn, """
        INSERT INTO users (data) VALUES 
        ($1), ($2), ($3)
      """, [
        %{"name" => "Alice", "tags" => ["elixir", "phoenix"]},
        %{"name" => "Bob", "tags" => ["ruby", "rails"]},
        %{"name" => "Charlie", "tags" => ["elixir", "ecto"]}
      ])

      # Yesqlクエリの実行
      # PostgrexはJSONB型を自動的に処理
      {:ok, results} = PostgresQueries.find_users_by_tag(conn, tag: ["elixir"])
      
      assert length(results) == 2
      names = results |> Enum.map(& &1.data["name"]) |> Enum.sort()
      assert names == ["Alice", "Charlie"]
    end

    test "JSONB属性検索", %{postgrex: conn} do
      # テストデータの挿入
      {:ok, _} = Postgrex.query(conn, """
        INSERT INTO users (data) VALUES 
        ($1), ($2)
      """, [
        %{"name" => "Alice", "role" => "admin", "active" => true},
        %{"name" => "Bob", "role" => "user", "active" => true}
      ])

      # 管理者の検索
      {:ok, results} = PostgresQueries.find_users_by_attributes(conn, 
        attributes: %{"role" => "admin"}
      )
      
      assert length(results) == 1
      assert hd(results).data["name"] == "Alice"
    end

    test "JSONBデータ更新", %{postgrex: conn} do
      # テストデータの挿入
      {:ok, result} = Postgrex.query(conn, """
        INSERT INTO users (data) VALUES ($1) RETURNING id
      """, [%{"name" => "Alice", "score" => 100}])
      
      user_id = result.rows |> hd |> hd

      # Yesqlで更新
      {:ok, [updated]} = PostgresQueries.update_user_data(conn,
        id: user_id,
        new_data: %{"score" => 150, "level" => "expert"}
      )

      assert updated.data["score"] == 150
      assert updated.data["level"] == "expert"
      assert updated.data["name"] == "Alice"
    end
  end

  describe "Yesql PostgreSQL 配列操作" do
    setup [:create_array_test_table]

    test "ANY演算子での検索", %{postgrex: conn} do
      # テストデータの挿入
      {:ok, _} = Postgrex.query(conn, """
        INSERT INTO items (name, tags) VALUES 
        ($1, $2), ($3, $4), ($5, $6)
      """, [
        "Item 1", ["electronics", "mobile"],
        "Item 2", ["books", "fiction"],
        "Item 3", ["electronics", "laptop"]
      ])

      # Yesqlクエリの実行
      {:ok, results} = PostgresQueries.find_by_any_tag(conn, tag: "electronics")
      
      assert length(results) == 2
      names = results |> Enum.map(& &1.name) |> Enum.sort()
      assert names == ["Item 1", "Item 3"]
    end

    test "配列の重複チェック", %{postgrex: conn} do
      # テストデータの挿入
      {:ok, _} = Postgrex.query(conn, """
        INSERT INTO items (name, tags) VALUES 
        ($1, $2), ($3, $4)
      """, [
        "Item 1", ["a", "b", "c"],
        "Item 2", ["d", "e", "f"]
      ])

      # 重複するタグを検索
      {:ok, results} = PostgresQueries.find_by_overlapping_tags(conn, 
        tags: ["b", "c", "x"]
      )
      
      assert length(results) == 1
      assert hd(results).name == "Item 1"
    end

    test "配列への要素追加", %{postgrex: conn} do
      # テストデータの挿入
      {:ok, result} = Postgrex.query(conn, """
        INSERT INTO items (name, tags) VALUES ($1, $2) RETURNING id
      """, ["Item 1", ["initial"]])
      
      item_id = result.rows |> hd |> hd

      # タグの追加
      {:ok, [updated]} = PostgresQueries.add_tags_to_item(conn,
        id: item_id,
        new_tags: ["added1", "added2"]
      )

      assert updated.tags == ["initial", "added1", "added2"]
    end
  end

  describe "Yesql PostgreSQL ウィンドウ関数" do
    setup [:create_sales_test_table]

    test "累積合計の計算", %{postgrex: conn} do
      # テストデータの挿入
      {:ok, _} = Postgrex.query(conn, """
        INSERT INTO sales (product, amount, sale_date) VALUES 
        ($1, $2, $3), ($4, $5, $6), ($7, $8, $9)
      """, [
        "Product A", Decimal.new(100), ~D[2024-01-01],
        "Product A", Decimal.new(150), ~D[2024-01-02],
        "Product A", Decimal.new(200), ~D[2024-01-03]
      ])

      # Yesqlクエリの実行
      {:ok, results} = PostgresQueries.sales_with_running_total(conn,
        start_date: ~D[2024-01-01],
        end_date: ~D[2024-01-31]
      )

      assert length(results) == 3
      
      # 累積合計の確認
      running_totals = results |> Enum.map(& &1.running_total)
      assert running_totals == [
        Decimal.new(100),
        Decimal.new(250),
        Decimal.new(450)
      ]
    end

    test "製品ランキング", %{postgrex: conn} do
      # テストデータの挿入
      {:ok, _} = Postgrex.query(conn, """
        INSERT INTO sales (product, amount, sale_date) VALUES 
        ($1, $2, $3), ($4, $5, $6), 
        ($7, $8, $9), ($10, $11, $12)
      """, [
        "Product A", Decimal.new(1000), ~D[2024-01-01],
        "Product A", Decimal.new(500), ~D[2024-01-02],
        "Product B", Decimal.new(800), ~D[2024-01-01],
        "Product C", Decimal.new(300), ~D[2024-01-01]
      ])

      # Yesqlクエリの実行
      {:ok, results} = PostgresQueries.rank_products_by_sales(conn,
        since: ~D[2024-01-01]
      )

      assert length(results) == 3
      
      # ランキングの確認
      first = hd(results)
      assert first.product == "Product A"
      assert first.total_sales == Decimal.new(1500)
      assert first.sales_rank == 1
    end
  end

  describe "Yesql PostgreSQL 再帰CTE" do
    setup [:create_hierarchy_test_table]

    test "階層構造の取得", %{postgrex: conn} do
      # テストデータの挿入
      {:ok, _} = Postgrex.query(conn, """
        INSERT INTO hierarchy (id, name, parent_id) VALUES 
        (1, 'Root', NULL),
        (2, 'Child 1', 1),
        (3, 'Child 2', 1),
        (4, 'Grandchild 1.1', 2),
        (5, 'Grandchild 2.1', 3)
      """, [])

      # Yesqlクエリの実行
      {:ok, results} = PostgresQueries.get_hierarchy_tree(conn, root_id: nil)

      assert length(results) == 5
      
      # レベルの確認
      root = Enum.find(results, & &1.name == "Root")
      assert root.level == 0
      
      grandchild = Enum.find(results, & &1.name == "Grandchild 1.1")
      assert grandchild.level == 2
      assert grandchild.full_path == "Root > Child 1 > Grandchild 1.1"
    end

    test "サブツリーの集計", %{postgrex: conn} do
      # テストデータの挿入
      {:ok, _} = Postgrex.query(conn, """
        INSERT INTO nodes (id, name, parent_id, value) VALUES 
        (1, 'Root', NULL, 10),
        (2, 'Child 1', 1, 20),
        (3, 'Child 2', 1, 30),
        (4, 'Grandchild', 2, 40)
      """, [])

      # Yesqlクエリの実行
      {:ok, [result]} = PostgresQueries.calculate_subtree_aggregates(conn, node_id: 1)

      assert result.node_count == 4
      assert result.total_value == 100
      assert result.avg_value == Decimal.new("25.00")
    end
  end

  describe "Yesql PostgreSQL 全文検索" do
    setup [:create_fulltext_test_table]

    test "基本的な全文検索", %{postgrex: conn} do
      # テストデータの挿入
      {:ok, _} = Postgrex.query(conn, """
        INSERT INTO documents (title, content, search_vector) VALUES 
        ($1, $2, to_tsvector('english', $1 || ' ' || $2)),
        ($3, $4, to_tsvector('english', $3 || ' ' || $4)),
        ($5, $6, to_tsvector('english', $5 || ' ' || $6))
      """, [
        "Elixir Programming", "Learn functional programming with Elixir",
        "Phoenix Framework", "Build web applications with Phoenix and Elixir",
        "Ruby Programming", "Object-oriented programming with Ruby"
      ])

      # Yesqlクエリの実行
      {:ok, results} = PostgresQueries.search_documents(conn,
        search_query: "elixir & programming",
        limit: 10
      )

      assert length(results) == 1
      assert hd(results).title == "Elixir Programming"
      assert hd(results).rank > 0
    end

    test "カテゴリ付き全文検索", %{postgrex: conn} do
      # カテゴリカラムの追加
      {:ok, _} = Postgrex.query(conn, 
        "ALTER TABLE documents ADD COLUMN IF NOT EXISTS category TEXT", [])

      # テストデータの挿入
      {:ok, _} = Postgrex.query(conn, """
        INSERT INTO documents (title, content, category, search_vector) VALUES 
        ($1, $2, $3, to_tsvector('english', $1 || ' ' || $2)),
        ($4, $5, $6, to_tsvector('english', $4 || ' ' || $5))
      """, [
        "Elixir Guide", "Complete guide to Elixir", "programming",
        "Phoenix Guide", "Complete guide to Phoenix", "framework"
      ])

      # Yesqlクエリの実行
      {:ok, results} = PostgresQueries.search_with_weights(conn,
        search_query: "guide",
        categories: ["programming", "tutorial"]
      )

      assert length(results) == 1
      assert hd(results).title == "Elixir Guide"
    end
  end

  # ヘルパー関数

  defp create_jsonb_test_table(%{postgrex: conn}) do
    {:ok, _} = Postgrex.query(conn, """
      CREATE TABLE IF NOT EXISTS users (
        id SERIAL PRIMARY KEY,
        data JSONB NOT NULL
      )
    """, [])
    
    {:ok, _} = Postgrex.query(conn, "TRUNCATE users", [])
    :ok
  end

  defp create_array_test_table(%{postgrex: conn}) do
    {:ok, _} = Postgrex.query(conn, """
      CREATE TABLE IF NOT EXISTS items (
        id SERIAL PRIMARY KEY,
        name TEXT NOT NULL,
        tags TEXT[]
      )
    """, [])
    
    {:ok, _} = Postgrex.query(conn, "TRUNCATE items", [])
    :ok
  end

  defp create_sales_test_table(%{postgrex: conn}) do
    {:ok, _} = Postgrex.query(conn, """
      CREATE TABLE IF NOT EXISTS sales (
        id SERIAL PRIMARY KEY,
        product TEXT NOT NULL,
        amount DECIMAL NOT NULL,
        sale_date DATE NOT NULL
      )
    """, [])
    
    {:ok, _} = Postgrex.query(conn, "TRUNCATE sales", [])
    :ok
  end

  defp create_hierarchy_test_table(%{postgrex: conn}) do
    {:ok, _} = Postgrex.query(conn, """
      CREATE TABLE IF NOT EXISTS hierarchy (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        parent_id INTEGER REFERENCES hierarchy(id)
      )
    """, [])
    
    {:ok, _} = Postgrex.query(conn, """
      CREATE TABLE IF NOT EXISTS nodes (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        parent_id INTEGER REFERENCES nodes(id),
        value INTEGER
      )
    """, [])
    
    {:ok, _} = Postgrex.query(conn, "TRUNCATE hierarchy CASCADE", [])
    {:ok, _} = Postgrex.query(conn, "TRUNCATE nodes CASCADE", [])
    :ok
  end

  defp create_fulltext_test_table(%{postgrex: conn}) do
    {:ok, _} = Postgrex.query(conn, """
      CREATE TABLE IF NOT EXISTS documents (
        id SERIAL PRIMARY KEY,
        title TEXT NOT NULL,
        content TEXT,
        search_vector TSVECTOR
      )
    """, [])
    
    {:ok, _} = Postgrex.query(conn, 
      "CREATE INDEX IF NOT EXISTS idx_documents_search ON documents USING GIN (search_vector)", [])
    
    {:ok, _} = Postgrex.query(conn, "TRUNCATE documents", [])
    :ok
  end
end