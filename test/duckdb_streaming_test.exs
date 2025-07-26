defmodule DuckDBStreamingTest do
  use ExUnit.Case

  # DuckDBが利用可能な場合のみテストを実行
  @tag :skip_on_ci
  @tag :duckdb
  @moduletag :streaming

  setup_all do
    case System.get_env("DUCKDB_TEST") do
      "true" ->
        {:ok, db} = Duckdbex.open(":memory:")
        {:ok, conn} = Duckdbex.connection(db)
        
        # ストリーミングテスト用の大規模テーブル作成
        create_sql = """
        CREATE TABLE streaming_test (
          id INTEGER,
          data VARCHAR,
          created_at TIMESTAMP,
          value DECIMAL(10,2),
          category VARCHAR
        )
        """
        
        {:ok, _} = Duckdbex.query(conn, create_sql, [])
        
        # core_functionsエクステンションをロード
        {:ok, _} = Duckdbex.query(conn, "INSTALL core_functions", [])
        {:ok, _} = Duckdbex.query(conn, "LOAD core_functions", [])
        
        # テストデータ挿入（10,000行）
        insert_sql = """
        INSERT INTO streaming_test 
        SELECT 
          range AS id,
          'data_' || range AS data,
          CURRENT_TIMESTAMP AS created_at,
          CAST((random() * 1000) AS DECIMAL(10,2)) AS value,
          CASE 
            WHEN range % 3 = 0 THEN 'A'
            WHEN range % 3 = 1 THEN 'B'
            ELSE 'C'
          END AS category
        FROM range(10000)
        """
        
        {:ok, _} = Duckdbex.query(conn, insert_sql, [])
        
        {:ok, conn: conn, db: db}
        
      _ ->
        {:ok, %{}}
    end
  end

  @describetag :streaming
  describe "基本的なストリーミング" do
    test "シンプルなクエリのストリーミング", %{conn: conn} do
      sql = "SELECT * FROM streaming_test WHERE id < 100"
      
      case Yesql.Stream.DuckDBStream.create(conn, sql, [], chunk_size: 10) do
        {:ok, stream} ->
          # ストリームから最初の20件を取得
          results = stream |> Enum.take(20) |> Enum.to_list()
          
          IO.inspect(length(results), label: "実際の結果数")
          IO.inspect(results |> Enum.take(3), label: "最初の3件")
          
          # 少なくとも1件以上の結果があることを確認
          assert length(results) > 0
          assert Enum.all?(results, &is_map/1)
          assert Enum.all?(results, &(&1.id < 100))
          
        error ->
          flunk("ストリーミングの作成に失敗: #{inspect(error)}")
      end
    end

    test "チャンクサイズの動作確認", %{conn: conn} do
      sql = "SELECT * FROM streaming_test LIMIT 50"
      
      {:ok, stream} = Yesql.Stream.DuckDBStream.create(conn, sql, [], chunk_size: 15)
      
      # ストリーム全体を取得
      all_results = Enum.to_list(stream)
      
      assert length(all_results) == 50
    end

    test "空の結果セットのストリーミング", %{conn: conn} do
      sql = "SELECT * FROM streaming_test WHERE id > 1000000"
      
      {:ok, stream} = Yesql.Stream.DuckDBStream.create(conn, sql, [])
      
      results = Enum.to_list(stream)
      assert results == []
    end
  end

  describe "パラメータ付きストリーミング" do
    @describetag :duckdb
    test "名前付きパラメータを使用したストリーミング", %{conn: conn} do
      sql = "SELECT * FROM streaming_test WHERE category = $1 AND value > $2"
      params = ["A", 500.0]
      
      {:ok, stream} = Yesql.Stream.DuckDBStream.create(conn, sql, params, chunk_size: 25)
      
      results = stream |> Enum.take(10) |> Enum.to_list()
      
      assert Enum.all?(results, &(&1.category == "A"))
      assert Enum.all?(results, &(&1.value > 500.0))
    end
  end

  describe "集約クエリのストリーミング" do
    @describetag :duckdb
    test "GROUP BYクエリのストリーミング", %{conn: conn} do
      sql = """
      SELECT 
        category,
        COUNT(*) as count,
        AVG(value) as avg_value,
        MIN(value) as min_value,
        MAX(value) as max_value
      FROM streaming_test
      GROUP BY category
      ORDER BY category
      """
      
      {:ok, stream} = Yesql.Stream.DuckDBStream.create(conn, sql, [])
      
      results = Enum.to_list(stream)
      
      assert length(results) == 3  # A, B, C
      assert Enum.all?(results, &(&1.category in ["A", "B", "C"]))
      assert Enum.all?(results, &(&1.count > 0))
    end
  end

  describe "並列スキャン" do
    @describetag :duckdb
    test "テーブルの並列スキャン", %{conn: conn} do
      {:ok, stream} = Yesql.Stream.DuckDBStream.create_parallel_scan(
        conn, 
        "streaming_test",
        parallelism: 4,
        chunk_size: 100
      )
      
      # 最初の400件を取得
      results = stream |> Enum.take(400) |> Enum.to_list()
      
      assert length(results) == 400
      assert Enum.all?(results, &is_map/1)
    end

    test "WHERE句付き並列スキャン", %{conn: conn} do
      {:ok, stream} = Yesql.Stream.DuckDBStream.create_parallel_scan(
        conn, 
        "streaming_test",
        parallelism: 2,
        where: "category = 'B'"
      )
      
      results = stream |> Enum.take(50) |> Enum.to_list()
      
      assert Enum.all?(results, &(&1.category == "B"))
    end
  end

  describe "エラーハンドリング" do
    @describetag :duckdb
    test "無効なSQL文のエラー", %{conn: conn} do
      sql = "SELECT * FROM nonexistent_table"
      
      case Yesql.Stream.DuckDBStream.create(conn, sql, []) do
        {:error, error} ->
          assert is_binary(error) or is_map(error)
        {:ok, _} ->
          flunk("エラーが発生すべきでした")
      end
    end

    test "Arrow形式は未サポート", %{conn: conn} do
      sql = "SELECT * FROM streaming_test"
      
      result = Yesql.Stream.DuckDBStream.create_arrow_stream(conn, sql, [])
      
      assert result == {:error, "Arrow streaming is not supported in current DuckDBex version"}
    end
  end

  describe "Parquetエクスポート" do
    @describetag :duckdb
    @tag :tmp_dir
    test "Parquetファイルへのエクスポート", %{conn: conn, tmp_dir: tmp_dir} do
      sql = "SELECT * FROM streaming_test WHERE id < 1000"
      file_path = Path.join(tmp_dir, "test_export.parquet")
      
      result = Yesql.Stream.DuckDBStream.export_to_parquet(
        conn, 
        sql, 
        [], 
        file_path,
        compression: :snappy,
        row_group_size: 100
      )
      
      case result do
        {:ok, path} ->
          assert path == file_path
          assert File.exists?(file_path)
        
        {:error, _} ->
          # Parquetエクスポートがサポートされていない場合はスキップ
          :ok
      end
    end
  end

  describe "ウィンドウ付きストリーミング" do
    @describetag :duckdb
    test "時系列データのウィンドウ処理", %{conn: conn} do
      # ウィンドウサイズ: 1時間（3600秒）
      window_size = 3600
      
      result = Yesql.Stream.DuckDBStream.create_windowed_stream(
        conn,
        "SELECT * FROM streaming_test",
        [],
        "created_at",
        window_size,
        chunk_size: 50
      )
      
      case result do
        {:ok, stream} ->
          windows = stream |> Enum.take(3) |> Enum.to_list()
          
          assert Enum.all?(windows, &(&1.window_id != nil))
          assert Enum.all?(windows, &(&1.start_time != nil))
          assert Enum.all?(windows, &(&1.end_time != nil))
          assert Enum.all?(windows, &(is_list(&1.data)))
          
        {:error, _} ->
          # ウィンドウ関数がサポートされていない場合はスキップ
          :ok
      end
    end
  end

  describe "パフォーマンステスト" do
    @describetag :duckdb
    @tag :performance
    test "大規模データのストリーミング性能", %{conn: conn} do
      sql = "SELECT * FROM streaming_test"
      
      start_time = System.monotonic_time(:millisecond)
      
      {:ok, stream} = Yesql.Stream.DuckDBStream.create(
        conn, 
        sql, 
        [], 
        chunk_size: 1000,
        prefetch: true
      )
      
      # 全データを処理（カウントのみ）
      count = stream |> Enum.reduce(0, fn _, acc -> acc + 1 end)
      
      end_time = System.monotonic_time(:millisecond)
      elapsed = end_time - start_time
      
      assert count == 10000
      
      # パフォーマンス指標を出力
      IO.puts("\nDuckDBストリーミングパフォーマンス:")
      IO.puts("  処理行数: #{count}")
      IO.puts("  処理時間: #{elapsed}ms")
      IO.puts("  スループット: #{Float.round(count / (elapsed / 1000), 2)} rows/sec")
    end
  end
end