defmodule PostgreSQLStreamingTest do
  use ExUnit.Case
  import TestHelper

  setup_all do
    case new_postgrex_connection(%{module: __MODULE__}) do
      {:ok, ctx} -> ctx
      _ -> 
        IO.puts("Skipping PostgreSQL Streaming tests - database connection failed")
        :skip
    end
  end

  describe "PostgreSQL ストリーミング機能" do
    setup [:create_streaming_test_table]

    test "Yesql.Streamを使用した大量データ処理", %{postgrex: conn} do
      # Yesql.Streamを使用してストリーミング処理
      {:ok, stream} = Yesql.Stream.query(conn, 
        "SELECT * FROM stream_test WHERE value > $1 ORDER BY id",
        [5000],
        driver: :postgrex,
        chunk_size: 1000
      )

      # ストリームから最初の10件を取得
      results = stream |> Enum.take(10)
      assert length(results) == 10
      assert Enum.all?(results, & &1.value > 5000)
    end

    test "ストリーミングでの集約処理", %{postgrex: conn} do
      # 合計値を計算（メモリ効率的）
      {:ok, total} = Yesql.Stream.reduce(conn,
        "SELECT value FROM stream_test WHERE value <= $1",
        [1000],
        0,
        fn row, acc -> acc + row.value end,
        driver: :postgrex,
        chunk_size: 500
      )

      # 期待値: 100 + 200 + ... + 1000 = 5500
      assert total == 5500
    end

    test "バッチ処理でのストリーミング", %{postgrex: conn} do
      processed_count = :counters.new(1, [])
      
      {:ok, batch_count} = Yesql.Stream.batch_process(conn,
        "SELECT * FROM stream_test ORDER BY id",
        [],
        100,  # バッチサイズ
        fn batch ->
          # バッチごとに処理
          :counters.add(processed_count, 1, length(batch))
        end,
        driver: :postgrex
      )

      total_processed = :counters.get(processed_count, 1)
      assert total_processed == 10000
      assert batch_count == 100  # 10000 / 100 = 100バッチ
    end

    test "フィルタリングとマッピングを含むストリーミング", %{postgrex: conn} do
      {:ok, stream} = Yesql.Stream.query(conn,
        "SELECT * FROM stream_test WHERE mod(value, $1) = 0",
        [100],  # 100の倍数のみ
        driver: :postgrex,
        chunk_size: 100
      )

      # ストリーミングで変換と収集
      results = stream
      |> Stream.map(fn row -> row.value * 2 end)
      |> Stream.filter(fn value -> value < 10000 end)
      |> Enum.to_list()

      assert length(results) == 49  # 100, 200, ..., 4900 の2倍
      assert Enum.all?(results, fn v -> rem(v, 200) == 0 and v < 10000 end)
    end

    test "ストリーミングでのエラーハンドリング", %{postgrex: conn} do
      # 存在しないテーブルへのクエリ
      result = Yesql.Stream.query(conn,
        "SELECT * FROM non_existent_table",
        [],
        driver: :postgrex
      )

      assert {:error, _} = result
    end

    test "大きなチャンクサイズでのストリーミング", %{postgrex: conn} do
      {:ok, stream} = Yesql.Stream.query(conn,
        "SELECT * FROM stream_test",
        [],
        driver: :postgrex,
        chunk_size: 5000  # 大きなチャンクサイズ
      )

      # 最初のチャンクを取得
      first_chunk = stream |> Enum.take(5000)
      assert length(first_chunk) == 5000
    end

    test "条件付きストリーミング処理", %{postgrex: conn} do
      sum_ref = :atomics.new(1, [])
      count_ref = :atomics.new(1, [])

      {:ok, _} = Yesql.Stream.process(conn,
        "SELECT * FROM stream_test WHERE value BETWEEN $1 AND $2",
        [1000, 5000],
        fn row ->
          if rem(row.value, 500) == 0 do
            :atomics.add(sum_ref, 1, row.value)
            :atomics.add(count_ref, 1, 1)
          end
        end,
        driver: :postgrex,
        chunk_size: 1000
      )

      total_sum = :atomics.get(sum_ref, 1)
      total_count = :atomics.get(count_ref, 1)

      # 1000, 1500, 2000, 2500, 3000, 3500, 4000, 4500, 5000
      assert total_count == 9
      assert total_sum == 27000
    end

    test "複数のストリーミングクエリの並行実行", %{postgrex: conn} do
      # 複数のストリームを作成
      {:ok, stream1} = Yesql.Stream.query(conn,
        "SELECT * FROM stream_test WHERE value < $1",
        [5000],
        driver: :postgrex,
        chunk_size: 1000
      )

      {:ok, stream2} = Yesql.Stream.query(conn,
        "SELECT * FROM stream_test WHERE value >= $1",
        [5000],
        driver: :postgrex,
        chunk_size: 1000
      )

      # 並行して処理
      task1 = Task.async(fn ->
        stream1 |> Enum.count()
      end)

      task2 = Task.async(fn ->
        stream2 |> Enum.count()
      end)

      count1 = Task.await(task1)
      count2 = Task.await(task2)

      assert count1 == 4999  # 100から4999まで
      assert count2 == 5001  # 5000から10000まで
      assert count1 + count2 == 10000
    end
  end

  describe "PostgreSQL カーソルベースストリーミング" do
    setup [:create_streaming_test_table]

    test "明示的なカーソル使用", %{postgrex: conn} do
      {:ok, result} = Postgrex.transaction(conn, fn conn ->
        # カーソルの宣言
        {:ok, _} = Postgrex.query(conn, """
          DECLARE large_cursor CURSOR FOR
          SELECT * FROM stream_test
          WHERE value BETWEEN $1 AND $2
          ORDER BY id
        """, [2000, 8000])

        # カーソルからデータを取得
        rows = fetch_all_from_cursor(conn, "large_cursor", 1000)
        
        # カーソルのクローズ
        {:ok, _} = Postgrex.query(conn, "CLOSE large_cursor", [])
        
        rows
      end)

      assert length(result) == 6001  # 2000から8000まで
    end

    test "複数カーソルの同時使用", %{postgrex: conn} do
      {:ok, {sum1, sum2}} = Postgrex.transaction(conn, fn conn ->
        # 2つのカーソルを宣言
        {:ok, _} = Postgrex.query(conn, """
          DECLARE cursor1 CURSOR FOR
          SELECT value FROM stream_test WHERE value < 5000
        """, [])

        {:ok, _} = Postgrex.query(conn, """
          DECLARE cursor2 CURSOR FOR
          SELECT value FROM stream_test WHERE value >= 5000
        """, [])

        # 両方のカーソルから交互にデータを取得
        sum1 = sum_from_cursor(conn, "cursor1", 500)
        sum2 = sum_from_cursor(conn, "cursor2", 500)

        # カーソルをクローズ
        {:ok, _} = Postgrex.query(conn, "CLOSE cursor1", [])
        {:ok, _} = Postgrex.query(conn, "CLOSE cursor2", [])

        {sum1, sum2}
      end)

      assert sum1 > 0
      assert sum2 > 0
      assert sum1 + sum2 == Enum.sum(100..10000)
    end
  end

  describe "PostgreSQL ストリーミングのパフォーマンス" do
    @tag :performance
    setup [:create_large_streaming_table]

    test "100万行のストリーミング処理", %{postgrex: conn} do
      start_time = System.monotonic_time(:millisecond)

      {:ok, count} = Yesql.Stream.process(conn,
        "SELECT id FROM large_stream_test",
        [],
        fn _row -> :ok end,
        driver: :postgrex,
        chunk_size: 10000
      )

      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time

      assert count == 1_000_000
      # パフォーマンスの確認（環境により異なる）
      IO.puts("Processed 1M rows in #{duration}ms")
      assert duration < 60_000  # 60秒以内
    end

    test "メモリ効率的な集計", %{postgrex: conn} do
      # メモリ使用量を監視しながら大量データを処理
      initial_memory = :erlang.memory(:total)

      {:ok, stats} = Yesql.Stream.reduce(conn,
        "SELECT category, value FROM large_stream_test",
        [],
        %{},
        fn row, acc ->
          Map.update(acc, row.category, row.value, &(&1 + row.value))
        end,
        driver: :postgrex,
        chunk_size: 5000
      )

      final_memory = :erlang.memory(:total)
      memory_increase = (final_memory - initial_memory) / 1_048_576  # MB

      assert map_size(stats) == 10  # 10カテゴリ
      assert Map.values(stats) |> Enum.all?(&(&1 > 0))
      
      # メモリ増加が合理的な範囲内
      IO.puts("Memory increase: #{Float.round(memory_increase, 2)}MB")
      assert memory_increase < 100  # 100MB以内
    end
  end

  # ヘルパー関数

  defp create_streaming_test_table(%{postgrex: conn}) do
    {:ok, _} = Postgrex.query(conn, """
      CREATE TABLE IF NOT EXISTS stream_test (
        id SERIAL PRIMARY KEY,
        value INTEGER NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    """, [])

    # データが存在しない場合のみ挿入
    {:ok, result} = Postgrex.query(conn, "SELECT COUNT(*) FROM stream_test", [])
    
    if result.rows == [[0]] do
      # バッチ挿入で10,000件のデータを作成
      Enum.chunk_every(100..10000, 1000)
      |> Enum.each(fn chunk ->
        values = chunk
        |> Enum.map(fn i -> "(#{i})" end)
        |> Enum.join(",")
        
        {:ok, _} = Postgrex.query(conn, """
          INSERT INTO stream_test (value) VALUES #{values}
        """, [])
      end)
    end

    :ok
  end

  defp create_large_streaming_table(%{postgrex: conn}) do
    {:ok, _} = Postgrex.query(conn, """
      CREATE TABLE IF NOT EXISTS large_stream_test (
        id SERIAL PRIMARY KEY,
        category VARCHAR(10),
        value INTEGER,
        data TEXT
      )
    """, [])

    # データが存在しない場合のみ挿入
    {:ok, result} = Postgrex.query(conn, "SELECT COUNT(*) FROM large_stream_test", [])
    
    if result.rows == [[0]] do
      IO.puts("Creating 1M test records... This may take a while.")
      
      # 100万件のデータを10,000件ずつバッチ挿入
      Enum.chunk_every(1..1_000_000, 10_000)
      |> Enum.with_index(1)
      |> Enum.each(fn {chunk, batch_num} ->
        if rem(batch_num, 10) == 0 do
          IO.puts("Progress: #{batch_num * 10_000} records inserted")
        end
        
        values = chunk
        |> Enum.map(fn i -> 
          category = "CAT#{rem(i, 10)}"
          value = rem(i, 1000)
          "('#{category}', #{value}, 'Data for record #{i}')"
        end)
        |> Enum.join(",")
        
        {:ok, _} = Postgrex.query(conn, """
          INSERT INTO large_stream_test (category, value, data) 
          VALUES #{values}
        """, [])
      end)
      
      IO.puts("Created 1M test records")
    end

    :ok
  end

  defp fetch_all_from_cursor(conn, cursor_name, chunk_size) do
    fetch_cursor_recursive(conn, cursor_name, chunk_size, [])
  end

  defp fetch_cursor_recursive(conn, cursor_name, chunk_size, acc) do
    {:ok, result} = Postgrex.query(conn, 
      "FETCH #{chunk_size} FROM #{cursor_name}", [])
    
    case result.rows do
      [] -> 
        acc
      rows ->
        new_rows = Enum.map(rows, fn [id, value, created_at] ->
          %{id: id, value: value, created_at: created_at}
        end)
        fetch_cursor_recursive(conn, cursor_name, chunk_size, acc ++ new_rows)
    end
  end

  defp sum_from_cursor(conn, cursor_name, chunk_size) do
    sum_cursor_recursive(conn, cursor_name, chunk_size, 0)
  end

  defp sum_cursor_recursive(conn, cursor_name, chunk_size, acc) do
    {:ok, result} = Postgrex.query(conn, 
      "FETCH #{chunk_size} FROM #{cursor_name}", [])
    
    case result.rows do
      [] -> 
        acc
      rows ->
        sum = rows |> Enum.map(&hd/1) |> Enum.sum()
        sum_cursor_recursive(conn, cursor_name, chunk_size, acc + sum)
    end
  end
end