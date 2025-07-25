defmodule Yesql.Stream.PostgrexStream do
  @moduledoc """
  PostgreSQL（Postgrex）用のストリーミング実装
  
  Postgrexの`stream/4`機能を使用して、大量のデータを効率的に処理します。
  """
  
  alias Yesql.Driver
  
  @doc """
  PostgreSQL用のストリームを作成
  
  ## オプション
  
    * `:max_rows` - 一度に取得する最大行数（デフォルト: 500）
    * `:decode_mapper` - カスタムデコーダー（省略可）
    * `:mode` - `:text`または`:binary`（デフォルト: `:text`）
  """
  def create(conn, sql, params, opts \\ []) do
    max_rows = Keyword.get(opts, :max_rows, 500)
    mode = Keyword.get(opts, :mode, :text)
    
    # Postgrexのトランザクション内でストリームを作成
    transaction_result = Postgrex.transaction(conn, fn tx_conn ->
      # CURSORを使用したストリーミング
      cursor_name = "yesql_cursor_#{:erlang.unique_integer([:positive])}"
      
      # CURSORを宣言
      declare_sql = "DECLARE #{cursor_name} CURSOR FOR #{sql}"
      case Postgrex.query(tx_conn, declare_sql, params) do
        {:ok, _} ->
          # ストリームを作成
          stream = create_cursor_stream(tx_conn, cursor_name, max_rows)
          {:ok, stream}
          
        error ->
          error
      end
    end)
    
    case transaction_result do
      {:ok, {:ok, stream}} -> {:ok, stream}
      {:ok, error} -> error
      error -> error
    end
  end
  
  @doc """
  非同期ストリーミング（大規模データセット用）
  
  別プロセスでストリーミングを実行し、データを非同期に処理します。
  """
  def create_async(conn, sql, params, opts \\ []) do
    parent = self()
    ref = make_ref()
    
    # ストリーミングプロセスを起動
    pid = spawn_link(fn ->
      case create(conn, sql, params, opts) do
        {:ok, stream} ->
          stream
          |> Stream.each(fn chunk ->
            send(parent, {ref, :data, chunk})
          end)
          |> Stream.run()
          
          send(parent, {ref, :done})
          
        {:error, reason} ->
          send(parent, {ref, :error, reason})
      end
    end)
    
    # 非同期ストリームを返す
    async_stream = Stream.resource(
      fn -> {ref, :continue} end,
      fn
        {^ref, :continue} ->
          receive do
            {^ref, :data, chunk} -> {[chunk], {ref, :continue}}
            {^ref, :done} -> {:halt, {ref, :done}}
            {^ref, :error, reason} -> throw({:error, reason})
          after
            5000 -> throw({:error, :timeout})
          end
          
        {^ref, :done} ->
          {:halt, {ref, :done}}
      end,
      fn _ -> Process.exit(pid, :kill) end
    )
    
    {:ok, async_stream}
  end
  
  @doc """
  ストリーミングクエリの統計情報を取得
  
  処理された行数、経過時間、メモリ使用量などの統計を取得します。
  """
  def with_stats(conn, sql, params, processor_fn, opts \\ []) do
    start_time = System.monotonic_time(:millisecond)
    initial_memory = :erlang.memory(:total)
    
    row_count = 0
    chunk_count = 0
    
    result = create(conn, sql, params, opts)
    |> case do
      {:ok, stream} ->
        final_count = stream
        |> Stream.map(fn chunk ->
          chunk_count = chunk_count + 1
          row_count = row_count + length(chunk)
          
          # チャンクを処理
          Enum.each(chunk, processor_fn)
          
          length(chunk)
        end)
        |> Enum.sum()
        
        {:ok, final_count}
        
      error ->
        error
    end
    
    end_time = System.monotonic_time(:millisecond)
    final_memory = :erlang.memory(:total)
    
    stats = %{
      row_count: row_count,
      chunk_count: chunk_count,
      duration_ms: end_time - start_time,
      memory_used: final_memory - initial_memory,
      rows_per_second: if(end_time > start_time, do: row_count * 1000 / (end_time - start_time), else: 0)
    }
    
    {result, stats}
  end
  
  # プライベート関数
  
  defp create_cursor_stream(conn, cursor_name, max_rows) do
    Stream.resource(
      # 初期化
      fn -> cursor_name end,
      
      # 次のチャンクを取得
      fn cursor ->
        fetch_sql = "FETCH #{max_rows} FROM #{cursor}"
        case Postgrex.query(conn, fetch_sql, []) do
          {:ok, %{rows: rows, columns: columns}} when rows != [] ->
            # 行をマップに変換
            processed_rows = Enum.map(rows, fn row ->
              columns
              |> Enum.zip(row)
              |> Enum.into(%{})
            end)
            
            {processed_rows, cursor}
            
          _ ->
            # データの終わりまたはエラー
            {:halt, cursor}
        end
      end,
      
      # クリーンアップ
      fn cursor ->
        # CURSORをクローズ
        Postgrex.query(conn, "CLOSE #{cursor}", [])
      end
    )
  end
  
  @doc """
  パラレルストリーミング（実験的機能）
  
  複数の接続を使用して並列にデータを取得します。
  """
  def create_parallel(pool, sql, params, opts \\ []) do
    parallelism = Keyword.get(opts, :parallelism, 4)
    max_rows = Keyword.get(opts, :max_rows, 500)
    
    # データを分割するための範囲を取得
    case get_data_ranges(pool, sql, params, parallelism) do
      {:ok, ranges} ->
        # 各範囲に対してストリームを作成
        streams = Enum.map(ranges, fn {start_id, end_id} ->
          # 範囲を追加したSQLを作成
          range_sql = add_range_condition(sql, start_id, end_id)
          
          Task.async(fn ->
            # プールから接続を取得
            :poolboy.transaction(pool, fn conn ->
              create(conn, range_sql, params, max_rows: max_rows)
            end)
          end)
        end)
        
        # 並列ストリームをマージ
        merged_stream = Stream.resource(
          fn -> {streams, []} end,
          fn {tasks, buffer} ->
            if buffer != [] do
              {buffer, {tasks, []}}
            else
              # 各タスクから結果を取得
              new_buffer = tasks
              |> Enum.flat_map(fn task ->
                case Task.yield(task, 100) do
                  {:ok, {:ok, stream}} ->
                    stream |> Enum.take(1) |> List.flatten()
                  _ ->
                    []
                end
              end)
              
              if new_buffer == [] do
                {:halt, {tasks, []}}
              else
                {new_buffer, {tasks, []}}
              end
            end
          end,
          fn {tasks, _} ->
            Enum.each(tasks, &Task.shutdown/1)
          end
        )
        
        {:ok, merged_stream}
        
      error ->
        error
    end
  end
  
  defp get_data_ranges(pool, sql, params, parallelism) do
    # SQLからテーブル名を抽出し、主キーの範囲を取得
    # これは簡略化された実装で、実際にはより複雑なロジックが必要
    {:ok, Enum.map(1..parallelism, fn i ->
      {(i - 1) * 100000, i * 100000}
    end)}
  end
  
  defp add_range_condition(sql, start_id, end_id) do
    # WHERE句に範囲条件を追加
    # これも簡略化された実装
    sql <> " AND id BETWEEN #{start_id} AND #{end_id}"
  end
end