defmodule StreamTest do
  use ExUnit.Case, async: false
  import TestHelper

  alias Yesql.Stream

  @moduletag :streaming

  setup_all do
    # PostgreSQL接続のセットアップ
    case new_postgrex_connection(%{module: __MODULE__}) do
      {:ok, ctx} ->
        # テストデータの準備
        conn = ctx[:postgrex]
        setup_postgresql_test_data(conn)
        ctx

      _ ->
        IO.puts("Skipping Stream tests - database connection failed")
        {:ok, skip: true}
    end
  end

  describe "基本的なストリーミング（PostgreSQL）" do
    test "大量データのストリーミング取得", %{postgrex: conn} do
      # テスト用SQL
      sql = "SELECT * FROM stream_test WHERE id <= $1 ORDER BY id"

      # ストリーミング実行
      {:ok, stream} =
        Stream.query(conn, sql, [5000],
          driver: :postgrex,
          chunk_size: 100
        )

      # データを収集
      results = stream |> Enum.to_list()

      assert length(results) == 5000
      assert hd(results)[:id] == 1
      assert List.last(results)[:id] == 5000
    end

    test "チャンクサイズの動作確認", %{postgrex: conn} do
      sql = "SELECT * FROM stream_test WHERE id <= $1 ORDER BY id"

      # 小さなチャンクサイズでストリーミング
      {:ok, stream} =
        Stream.query(conn, sql, [100],
          driver: :postgrex,
          chunk_size: 10
        )

      # データを全て取得
      results = stream |> Enum.to_list()
      
      assert length(results) == 100
    end
  end

  describe "ストリーミング処理" do
    test "process関数でのデータ処理", %{postgrex: conn} do
      sql = "SELECT * FROM stream_test WHERE id <= $1 ORDER BY id"

      # カウンターを使用してデータ処理
      {:ok, pid} = Agent.start_link(fn -> 0 end)

      {:ok, count} =
        Stream.process(
          conn,
          sql,
          [1000],
          fn row ->
            Agent.update(pid, &(&1 + row[:value]))
          end,
          driver: :postgrex,
          chunk_size: 50
        )

      assert count == 1000

      # 合計値を確認（100から1099までの合計）
      total = Agent.get(pid, & &1)
      expected_total = Enum.sum(100..1099)
      assert total == expected_total

      Agent.stop(pid)
    end

    test "reduce関数での集約処理", %{postgrex: conn} do
      sql = "SELECT * FROM stream_test WHERE id <= $1 ORDER BY id"

      # 最大値を計算
      {:ok, max_value} =
        Stream.reduce(
          conn,
          sql,
          [1000],
          0,
          fn row, acc ->
            max(row[:value], acc)
          end,
          driver: :postgrex
        )

      assert max_value == 1099
    end

    test "batch_process関数でのバッチ処理", %{postgrex: conn} do
      sql = "SELECT * FROM stream_test WHERE id <= $1 ORDER BY id"

      batch_counts = []

      {:ok, batch_count} =
        Stream.batch_process(
          conn,
          sql,
          [1000],
          100,
          fn _batch ->
            # バッチサイズを記録
            batch_counts
          end,
          driver: :postgrex
        )

      # 1000 / 100 = 10
      assert batch_count == 10
    end
  end

  describe "メモリ効率性" do
    test "大量データでのメモリ使用量", %{postgrex: conn} do
      initial_memory = :erlang.memory(:total)

      # 10,000件のデータをストリーミング処理
      {:ok, _} =
        Stream.process(
          conn,
          "SELECT * FROM stream_test WHERE id <= $1",
          [10_000],
          fn _row ->
            # 処理のみ、蓄積しない
            :ok
          end,
          driver: :postgrex,
          chunk_size: 1000
        )

      final_memory = :erlang.memory(:total)
      memory_increase = final_memory - initial_memory

      # メモリ増加が妥当な範囲内（100MB以下）
      assert memory_increase < 100 * 1024 * 1024
    end
  end

  describe "エラーハンドリング" do
    test "無効なSQL", %{postgrex: conn} do
      result = Stream.query(conn, "INVALID SQL", [], driver: :postgrex)

      assert {:error, _} = result
    end

    test "存在しないテーブル", %{postgrex: conn} do
      result = Stream.query(
        conn, 
        "SELECT * FROM non_existent_table", 
        [], 
        driver: :postgrex
      )

      assert {:error, _} = result
    end
  end

  # ヘルパー関数

  defp setup_postgresql_test_data(conn) do
    # テーブルを作成
    {:ok, _} = Postgrex.query(conn, "DROP TABLE IF EXISTS stream_test", [])

    {:ok, _} = Postgrex.query(
      conn,
      """
      CREATE TABLE stream_test (
        id SERIAL PRIMARY KEY,
        value INTEGER NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
      """,
      []
    )

    # バッチ挿入で10,000件のデータを作成
    Enum.chunk_every(100..10099, 1000)
    |> Enum.each(fn chunk ->
      values =
        chunk
        |> Enum.map(fn i -> "(#{i})" end)
        |> Enum.join(",")

      {:ok, _} = Postgrex.query(
        conn,
        "INSERT INTO stream_test (value) VALUES #{values}",
        []
      )
    end)
  end
end