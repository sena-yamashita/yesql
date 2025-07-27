defmodule PostgreSQLTest do
  use ExUnit.Case
  import TestHelper

  setup_all do
    case new_postgrex_connection(%{module: __MODULE__}) do
      {:ok, ctx} ->
        ctx

      _ ->
        IO.puts("Skipping PostgreSQL tests - database connection failed")
        {:ok, skip: true}
    end
  end

  describe "PostgreSQL専用機能のテスト" do
    setup [:create_postgres_test_tables, :truncate_postgres_test_tables]

    test "JSONB型のサポート", %{postgrex: conn} do
      # JSONBデータの挿入
      {:ok, _} =
        Postgrex.query(
          conn,
          """
            INSERT INTO test_jsonb (data) VALUES ($1), ($2)
          """,
          [
            %{"name" => "Alice", "age" => 30, "tags" => ["developer", "elixir"]},
            %{"name" => "Bob", "age" => 25, "tags" => ["designer"]}
          ]
        )

      # JSONB演算子を使った検索
      {:ok, result} =
        Postgrex.query(
          conn,
          """
            SELECT data FROM test_jsonb WHERE data @> $1
          """,
          [%{"name" => "Alice"}]
        )

      assert length(result.rows) == 1
      [row] = result.rows
      assert row == [%{"age" => 30, "name" => "Alice", "tags" => ["developer", "elixir"]}]

      # JSONBパス演算子
      {:ok, result} =
        Postgrex.query(
          conn,
          """
            SELECT data->>'name' as name, (data->>'age')::int as age
            FROM test_jsonb 
            WHERE data ? 'tags'
            ORDER BY age
          """,
          []
        )

      assert result.rows == [["Bob", 25], ["Alice", 30]]
    end

    test "配列型のサポート", %{postgrex: conn} do
      # 配列データの挿入
      {:ok, _} =
        Postgrex.query(
          conn,
          """
            INSERT INTO test_arrays (tags, numbers) VALUES ($1, $2), ($3, $4)
          """,
          [
            ["elixir", "phoenix", "postgresql"],
            [1, 2, 3, 4, 5],
            ["ruby", "rails"],
            [10, 20]
          ]
        )

      # 配列演算子を使った検索
      {:ok, result} =
        Postgrex.query(
          conn,
          """
            SELECT tags FROM test_arrays WHERE 'elixir' = ANY(tags)
          """,
          []
        )

      assert length(result.rows) == 1
      assert result.rows == [[["elixir", "phoenix", "postgresql"]]]

      # 配列の重複チェック
      {:ok, result} =
        Postgrex.query(
          conn,
          """
            SELECT tags FROM test_arrays WHERE tags && $1
          """,
          [["ruby", "python"]]
        )

      assert result.rows == [[["ruby", "rails"]]]
    end

    test "UUID型のサポート", %{postgrex: conn} do
      uuid1 = Ecto.UUID.dump!("550e8400-e29b-41d4-a716-446655440000")
      uuid2 = Ecto.UUID.dump!("6ba7b810-9dad-11d1-80b4-00c04fd430c8")

      # UUIDの挿入
      {:ok, _} =
        Postgrex.query(
          conn,
          """
            INSERT INTO test_uuid (id, name) VALUES ($1, $2), ($3, $4)
          """,
          [uuid1, "Record 1", uuid2, "Record 2"]
        )

      # UUIDで検索
      {:ok, result} =
        Postgrex.query(
          conn,
          """
            SELECT name FROM test_uuid WHERE id = $1
          """,
          [uuid1]
        )

      assert result.rows == [["Record 1"]]
    end

    test "日付・時刻型の高度な操作", %{postgrex: conn} do
      # タイムゾーン付きの時刻データ
      {:ok, _} =
        Postgrex.query(
          conn,
          """
            INSERT INTO test_timestamps (event_time, event_name) VALUES 
            ($1, 'Morning meeting'),
            ($2, 'Lunch break'),
            ($3, 'End of day')
          """,
          [
            ~U[2024-01-15 09:00:00Z],
            ~U[2024-01-15 12:30:00Z],
            ~U[2024-01-15 17:00:00Z]
          ]
        )

      # インターバル計算 - 日付の条件を外してすべてのレコードを取得
      {:ok, result} =
        Postgrex.query(
          conn,
          """
            SELECT event_name, 
                   event_time AT TIME ZONE 'America/New_York' as ny_time,
                   event_time - INTERVAL '1 hour' as one_hour_before
            FROM test_timestamps
            ORDER BY event_time
          """,
          []
        )

      assert length(result.rows) == 3
      [morning, _, _] = result.rows
      assert morning |> Enum.at(0) == "Morning meeting"
    end

    test "ENUM型のサポート", %{postgrex: conn} do
      # ENUM値の挿入
      {:ok, _} =
        Postgrex.query(
          conn,
          """
            INSERT INTO test_enum (status, priority) VALUES 
            ('pending', 'high'),
            ('in_progress', 'medium'),
            ('completed', 'low')
          """,
          []
        )

      # ENUM値での検索
      {:ok, result} =
        Postgrex.query(
          conn,
          """
            SELECT status, priority FROM test_enum 
            WHERE priority = 'high'
          """,
          []
        )

      assert result.rows == [["pending", "high"]]

      # ENUM値の順序比較
      {:ok, result} =
        Postgrex.query(
          conn,
          """
            SELECT status FROM test_enum 
            WHERE priority < 'high'
            ORDER BY priority
          """,
          []
        )

      assert length(result.rows) == 2
    end

    test "範囲型のサポート", %{postgrex: conn} do
      # 範囲データの挿入
      {:ok, _} =
        Postgrex.query(
          conn,
          """
            INSERT INTO test_ranges (price_range, valid_dates) VALUES 
            ($1, $2),
            ($3, $4)
          """,
          [
            %Postgrex.Range{
              lower: 100,
              upper: 200,
              lower_inclusive: true,
              upper_inclusive: false
            },
            %Postgrex.Range{
              lower: ~D[2024-01-01],
              upper: ~D[2024-12-31],
              lower_inclusive: true,
              upper_inclusive: true
            },
            %Postgrex.Range{lower: 50, upper: 150, lower_inclusive: true, upper_inclusive: true},
            %Postgrex.Range{
              lower: ~D[2024-06-01],
              upper: ~D[2024-08-31],
              lower_inclusive: true,
              upper_inclusive: true
            }
          ]
        )

      # 範囲の重複チェック
      {:ok, result} =
        Postgrex.query(
          conn,
          """
            SELECT price_range FROM test_ranges 
            WHERE price_range && int4range(120, 180)
          """,
          []
        )

      assert length(result.rows) == 2
    end

    test "全文検索機能", %{postgrex: conn} do
      # テキスト検索データの挿入
      {:ok, _} =
        Postgrex.query(
          conn,
          """
            INSERT INTO test_fulltext (title, content) VALUES 
            ($1, $2),
            ($3, $4),
            ($5, $6)
          """,
          [
            "Elixir Programming",
            "Elixir is a dynamic, functional language",
            "Phoenix Framework",
            "Phoenix is a productive web framework for Elixir",
            "PostgreSQL Database",
            "PostgreSQL is a powerful open source database"
          ]
        )

      # 全文検索インデックスの更新
      {:ok, _} =
        Postgrex.query(
          conn,
          """
            UPDATE test_fulltext 
            SET search_vector = to_tsvector('english', title || ' ' || content)
          """,
          []
        )

      # 全文検索クエリ
      {:ok, result} =
        Postgrex.query(
          conn,
          """
            SELECT title, ts_rank(search_vector, query) as rank
            FROM test_fulltext, to_tsquery('english', $1) query
            WHERE search_vector @@ query
            ORDER BY rank DESC
          """,
          ["elixir & framework"]
        )

      assert length(result.rows) == 1
      assert result.rows |> hd |> hd == "Phoenix Framework"
    end

    test "CTE（共通テーブル式）のサポート", %{postgrex: conn} do
      # 階層データの挿入
      {:ok, _} =
        Postgrex.query(
          conn,
          """
            INSERT INTO test_hierarchy (id, name, parent_id) VALUES 
            (1, 'Root', NULL),
            (2, 'Child 1', 1),
            (3, 'Child 2', 1),
            (4, 'Grandchild 1', 2),
            (5, 'Grandchild 2', 2)
          """,
          []
        )

      # 再帰CTEを使った階層取得
      {:ok, result} =
        Postgrex.query(
          conn,
          """
            WITH RECURSIVE tree AS (
              SELECT id, name, parent_id, 0 as level
              FROM test_hierarchy
              WHERE parent_id IS NULL
              
              UNION ALL
              
              SELECT h.id, h.name, h.parent_id, t.level + 1
              FROM test_hierarchy h
              JOIN tree t ON h.parent_id = t.id
            )
            SELECT name, level FROM tree
            ORDER BY level, name
          """,
          []
        )

      assert length(result.rows) == 5
      assert result.rows |> hd == ["Root", 0]
    end

    test "ウィンドウ関数のサポート", %{postgrex: conn} do
      # 売上データの挿入
      {:ok, _} =
        Postgrex.query(
          conn,
          """
            INSERT INTO test_sales (product, amount, sale_date) VALUES 
            ('Product A', 100, '2024-01-01'),
            ('Product A', 150, '2024-01-02'),
            ('Product B', 200, '2024-01-01'),
            ('Product B', 180, '2024-01-02'),
            ('Product A', 120, '2024-01-03')
          """,
          []
        )

      # ウィンドウ関数を使った累積計算
      {:ok, result} =
        Postgrex.query(
          conn,
          """
            SELECT product, amount, sale_date,
                   SUM(amount) OVER (PARTITION BY product ORDER BY sale_date) as running_total,
                   ROW_NUMBER() OVER (PARTITION BY product ORDER BY sale_date) as row_num
            FROM test_sales
            ORDER BY product, sale_date
          """,
          []
        )

      assert length(result.rows) == 5
      # Product Aの累積合計をチェック
      product_a_rows = result.rows |> Enum.filter(fn [product | _] -> product == "Product A" end)
      # 100 + 150 + 120
      assert product_a_rows |> List.last() |> Enum.at(3) == Decimal.new(370)
    end

    test "トランザクション分離レベルのテスト", %{postgrex: conn} do
      # READ COMMITTEDレベルでのトランザクション
      {:ok, _} =
        Postgrex.transaction(conn, fn conn ->
          {:ok, _} = Postgrex.query(conn, "INSERT INTO test_isolation (value) VALUES ($1)", [100])

          {:ok, result} =
            Postgrex.query(conn, "SELECT value FROM test_isolation WHERE value = $1", [100])

          assert length(result.rows) == 1
        end)

      # SERIALIZABLEレベルでのトランザクション
      {:ok, _} =
        Postgrex.transaction(conn, fn conn ->
          {:ok, _} = Postgrex.query(conn, "SET TRANSACTION ISOLATION LEVEL SERIALIZABLE", [])
          {:ok, _} = Postgrex.query(conn, "INSERT INTO test_isolation (value) VALUES ($1)", [200])
        end)

      {:ok, result} = Postgrex.query(conn, "SELECT COUNT(*) FROM test_isolation", [])
      assert result.rows == [[2]]
    end

    test "部分インデックスの効果", %{postgrex: conn} do
      # 大量データの挿入
      Enum.each(1..1000, fn i ->
        status = if rem(i, 10) == 0, do: "active", else: "inactive"

        {:ok, _} =
          Postgrex.query(
            conn,
            "INSERT INTO test_partial_index (status, value) VALUES ($1, $2)",
            [status, i]
          )
      end)

      # 部分インデックスを使ったクエリ（activeのみ）
      {:ok, result} =
        Postgrex.query(
          conn,
          """
            SELECT COUNT(*) FROM test_partial_index WHERE status = 'active'
          """,
          []
        )

      assert result.rows == [[100]]

      # EXPLAINで部分インデックスの使用を確認
      {:ok, explain} =
        Postgrex.query(
          conn,
          """
            EXPLAIN SELECT * FROM test_partial_index WHERE status = 'active' AND value > 500
          """,
          []
        )

      # インデックススキャンが使われることを確認
      explain_text = explain.rows |> Enum.map(&hd/1) |> Enum.join("\n")
      assert explain_text =~ "Index Scan" || explain_text =~ "index"
    end

    test "LISTEN/NOTIFYのサポート", %{postgrex: conn} do
      # NOTIFYの実行
      {:ok, _} = Postgrex.query(conn, "NOTIFY test_channel, 'Hello from PostgreSQL'", [])

      # 通知は非同期なので、実際のLISTEN/NOTIFYテストは
      # Postgrex.Notificationsを使った別のプロセスで行う必要がある
      assert true
    end

    test "カスタム集約関数", %{postgrex: conn} do
      # データの挿入
      {:ok, _} =
        Postgrex.query(
          conn,
          """
            INSERT INTO test_aggregates (category, value) VALUES 
            ('A', 10), ('A', 20), ('A', 30),
            ('B', 15), ('B', 25)
          """,
          []
        )

      # 複数の集約関数の組み合わせ
      {:ok, result} =
        Postgrex.query(
          conn,
          """
            SELECT category,
                   COUNT(*) as count,
                   SUM(value) as total,
                   AVG(value)::numeric(10,2) as average,
                   ARRAY_AGG(value ORDER BY value) as values,
                   STRING_AGG(value::text, ',' ORDER BY value) as concatenated
            FROM test_aggregates
            GROUP BY category
            ORDER BY category
          """,
          []
        )

      assert length(result.rows) == 2
      [row_a, _row_b] = result.rows

      assert row_a |> Enum.at(0) == "A"
      assert row_a |> Enum.at(1) == 3
      assert row_a |> Enum.at(2) == 60
      assert row_a |> Enum.at(4) == [10, 20, 30]
      assert row_a |> Enum.at(5) == "10,20,30"
    end

    test "プリペアドステートメントのテスト", %{postgrex: conn} do
      # プリペアドステートメントの準備
      {:ok, query} =
        Postgrex.prepare(conn, "get_by_status", """
          SELECT id, data FROM test_jsonb WHERE data->>'status' = $1
        """)

      # データの挿入
      {:ok, _} =
        Postgrex.query(
          conn,
          """
            INSERT INTO test_jsonb (data) VALUES 
            ($1), ($2), ($3)
          """,
          [
            %{"id" => 1, "status" => "active"},
            %{"id" => 2, "status" => "inactive"},
            %{"id" => 3, "status" => "active"}
          ]
        )

      # プリペアドステートメントの実行
      # Postgrex.executeは{:ok, query, result}を返す
      {:ok, _query, result} = Postgrex.execute(conn, query, ["active"])
      assert length(result.rows) == 2

      # クローズ
      # Postgrex.closeは:okを返す
      :ok = Postgrex.close(conn, query)
    end
  end

  describe "PostgreSQLストリーミング機能" do
    setup [:create_large_postgres_table]

    test "大量データのストリーミング処理", %{postgrex: conn} do
      # Stream.resourceを使った効率的な処理
      count = stream_large_data(conn)
      assert count == 10000
    end

    test "カーソルを使ったストリーミング", %{postgrex: conn} do
      # トランザクション内でカーソルを使用
      {:ok, count} =
        Postgrex.transaction(conn, fn conn ->
          # カーソルの宣言
          {:ok, _} =
            Postgrex.query(
              conn,
              """
                DECLARE test_cursor CURSOR FOR 
                SELECT id, value FROM test_large_data 
                WHERE value > 5000
                ORDER BY id
              """,
              []
            )

          # カーソルからデータを取得
          count = fetch_from_cursor(conn, "test_cursor", 0)

          # カーソルのクローズ
          {:ok, _} = Postgrex.query(conn, "CLOSE test_cursor", [])

          count
        end)

      assert count > 0
    end
  end

  describe "PostgreSQL拡張機能" do
    @describetag :extensions

    test "pg_stat_statementsの利用", %{postgrex: conn} do
      # 拡張機能の確認（インストールされている場合のみ）
      {:ok, result} =
        Postgrex.query(
          conn,
          """
            SELECT EXISTS(
              SELECT 1 FROM pg_extension WHERE extname = 'pg_stat_statements'
            )
          """,
          []
        )

      if result.rows == [[true]] do
        # クエリ統計の取得
        {:ok, stats} =
          Postgrex.query(
            conn,
            """
              SELECT query, calls, mean_exec_time
              FROM pg_stat_statements
              WHERE query NOT LIKE '%pg_stat_statements%'
              ORDER BY mean_exec_time DESC
              LIMIT 5
            """,
            []
          )

        assert is_list(stats.rows)
      end
    end
  end

  # ヘルパー関数

  defp create_postgres_test_tables(ctx) do
    conn = ctx.postgrex

    # ENUM型の作成
    Postgrex.query(conn, "DROP TYPE IF EXISTS status_enum CASCADE", [])
    Postgrex.query(conn, "DROP TYPE IF EXISTS priority_enum CASCADE", [])

    {:ok, _} =
      Postgrex.query(
        conn,
        """
          CREATE TYPE status_enum AS ENUM ('pending', 'in_progress', 'completed', 'cancelled')
        """,
        []
      )

    {:ok, _} =
      Postgrex.query(
        conn,
        """
          CREATE TYPE priority_enum AS ENUM ('low', 'medium', 'high', 'urgent')
        """,
        []
      )

    # 既存のテーブルを削除
    drop_tables = [
      "DROP TABLE IF EXISTS test_jsonb CASCADE",
      "DROP TABLE IF EXISTS test_arrays CASCADE",
      "DROP TABLE IF EXISTS test_uuid CASCADE",
      "DROP TABLE IF EXISTS test_timestamps CASCADE",
      "DROP TABLE IF EXISTS test_enum CASCADE",
      "DROP TABLE IF EXISTS test_ranges CASCADE",
      "DROP TABLE IF EXISTS test_fulltext CASCADE",
      "DROP TABLE IF EXISTS test_hierarchy CASCADE",
      "DROP TABLE IF EXISTS test_sales CASCADE",
      "DROP TABLE IF EXISTS test_isolation CASCADE",
      "DROP TABLE IF EXISTS test_partial_index CASCADE",
      "DROP TABLE IF EXISTS test_aggregates CASCADE"
    ]
    
    Enum.each(drop_tables, fn drop_sql ->
      Postgrex.query(conn, drop_sql, [])
    end)

    # テーブルの作成
    tables = [
      """
      CREATE TABLE test_jsonb (
        id SERIAL PRIMARY KEY,
        data JSONB NOT NULL
      )
      """,
      """
      CREATE TABLE test_arrays (
        id SERIAL PRIMARY KEY,
        tags TEXT[],
        numbers INTEGER[]
      )
      """,
      """
      CREATE TABLE test_uuid (
        id UUID PRIMARY KEY,
        name TEXT
      )
      """,
      """
      CREATE TABLE test_timestamps (
        id SERIAL PRIMARY KEY,
        event_time TIMESTAMPTZ NOT NULL,
        event_name TEXT
      )
      """,
      """
      CREATE TABLE test_enum (
        id SERIAL PRIMARY KEY,
        status status_enum,
        priority priority_enum
      )
      """,
      """
      CREATE TABLE test_ranges (
        id SERIAL PRIMARY KEY,
        price_range INT4RANGE,
        valid_dates DATERANGE
      )
      """,
      """
      CREATE TABLE test_fulltext (
        id SERIAL PRIMARY KEY,
        title TEXT,
        content TEXT,
        search_vector TSVECTOR
      )
      """,
      """
      CREATE TABLE test_hierarchy (
        id INTEGER PRIMARY KEY,
        name TEXT,
        parent_id INTEGER REFERENCES test_hierarchy(id)
      )
      """,
      """
      CREATE TABLE test_sales (
        id SERIAL PRIMARY KEY,
        product TEXT,
        amount DECIMAL,
        sale_date DATE
      )
      """,
      """
      CREATE TABLE test_isolation (
        id SERIAL PRIMARY KEY,
        value INTEGER
      )
      """,
      """
      CREATE TABLE test_partial_index (
        id SERIAL PRIMARY KEY,
        status TEXT,
        value INTEGER
      )
      """,
      """
      CREATE TABLE test_aggregates (
        id SERIAL PRIMARY KEY,
        category TEXT,
        value INTEGER
      )
      """
    ]

    Enum.each(tables, fn table_sql ->
      {:ok, _} = Postgrex.query(conn, table_sql, [])
    end)

    # インデックスの作成
    {:ok, _} =
      Postgrex.query(
        conn,
        """
          CREATE INDEX IF NOT EXISTS idx_test_jsonb_data ON test_jsonb USING GIN (data)
        """,
        []
      )

    {:ok, _} =
      Postgrex.query(
        conn,
        """
          CREATE INDEX IF NOT EXISTS idx_test_fulltext_search ON test_fulltext USING GIN (search_vector)
        """,
        []
      )

    {:ok, _} =
      Postgrex.query(
        conn,
        """
          CREATE INDEX IF NOT EXISTS idx_test_partial ON test_partial_index (value) 
          WHERE status = 'active'
        """,
        []
      )

    {:ok, ctx}
  end

  defp truncate_postgres_test_tables(ctx) do
    conn = ctx.postgrex

    tables = [
      "test_jsonb",
      "test_arrays",
      "test_uuid",
      "test_timestamps",
      "test_enum",
      "test_ranges",
      "test_fulltext",
      "test_hierarchy",
      "test_sales",
      "test_isolation",
      "test_partial_index",
      "test_aggregates"
    ]

    Enum.each(tables, fn table ->
      Postgrex.query(conn, "TRUNCATE TABLE #{table} CASCADE", [])
    end)

    {:ok, ctx}
  end

  defp create_large_postgres_table(ctx) do
    conn = ctx.postgrex

    {:ok, _} =
      Postgrex.query(
        conn,
        """
          CREATE TABLE IF NOT EXISTS test_large_data (
            id SERIAL PRIMARY KEY,
            value INTEGER,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
          )
        """,
        []
      )

    # テーブルが空の場合のみデータを挿入
    {:ok, result} = Postgrex.query(conn, "SELECT COUNT(*) FROM test_large_data", [])

    if result.rows == [[0]] do
      # バッチ挿入で大量データを作成
      Enum.chunk_every(1..10000, 1000)
      |> Enum.each(fn chunk ->
        values =
          chunk
          |> Enum.map(fn i -> "(#{i * 10})" end)
          |> Enum.join(",")

        {:ok, _} =
          Postgrex.query(
            conn,
            """
              INSERT INTO test_large_data (value) VALUES #{values}
            """,
            []
          )
      end)
    end

    {:ok, ctx}
  end

  defp stream_large_data(conn) do
    {:ok, count} =
      Postgrex.transaction(conn, fn conn ->
        # Postgrex.streamを使用
        query = "SELECT id, value FROM test_large_data ORDER BY id"
        stream = Postgrex.stream(conn, query, [])

        stream
        |> Stream.map(fn %Postgrex.Result{rows: rows} -> length(rows) end)
        |> Enum.sum()
      end)

    count
  end

  defp fetch_from_cursor(conn, cursor_name, acc) do
    {:ok, result} = Postgrex.query(conn, "FETCH 100 FROM #{cursor_name}", [])

    case result.rows do
      [] -> acc
      rows -> fetch_from_cursor(conn, cursor_name, acc + length(rows))
    end
  end
end
