defmodule Yesql.Stream.OracleStream do
  @moduledoc """
  Oracle Database用のストリーミングサポート
  
  jamdb_oracleドライバーを使用して、Oracleの高度な機能を活用：
  
  1. REF CURSORを使用したカーソルベースストリーミング
  2. BULK COLLECTによる効率的なデータフェッチ
  3. パラレル実行のサポート
  4. ROWNUMベースのページネーション
  """
  
  alias Yesql.Driver.OracleDriver
  
  @default_chunk_size 1000
  @max_array_size 10000
  
  @doc """
  ストリームを作成する（REF CURSORベース）
  """
  def create(conn, sql, params, opts \\ []) do
    chunk_size = Keyword.get(opts, :chunk_size, @default_chunk_size)
    use_parallel = Keyword.get(opts, :parallel, false)
    
    # パラレル実行のヒント追加
    optimized_sql = if use_parallel do
      "SELECT /*+ PARALLEL(4) */ * FROM (#{sql})"
    else
      sql
    end
    
    # REF CURSORの作成
    cursor_name = "cur_#{:erlang.unique_integer([:positive])}"
    
    cursor_sql = """
    DECLARE
      #{cursor_name} SYS_REFCURSOR;
    BEGIN
      OPEN #{cursor_name} FOR
        #{optimized_sql};
      :cursor := #{cursor_name};
    END;
    """
    
    case execute_with_cursor(conn, cursor_sql, params) do
      {:ok, cursor} ->
        stream = create_cursor_stream(conn, cursor, chunk_size)
        {:ok, stream}
      {:error, reason} ->
        {:error, reason}
    end
  rescue
    e -> {:error, e}
  end
  
  @doc """
  BULK COLLECTを使用した高速ストリーミング
  """
  def create_bulk_collect_stream(conn, sql, params, opts \\ []) do
    chunk_size = Keyword.get(opts, :chunk_size, @default_chunk_size)
    
    # PL/SQLブロックでBULK COLLECTを実装
    plsql = """
    DECLARE
      TYPE t_cursor IS REF CURSOR;
      v_cursor t_cursor;
      TYPE t_data IS TABLE OF VARCHAR2(4000);
      v_data t_data;
      v_json CLOB;
    BEGIN
      OPEN v_cursor FOR #{sql};
      
      LOOP
        FETCH v_cursor BULK COLLECT INTO v_data LIMIT :chunk_size;
        
        IF v_data.COUNT = 0 THEN
          EXIT;
        END IF;
        
        -- データをJSON形式で返す
        v_json := '[';
        FOR i IN 1..v_data.COUNT LOOP
          IF i > 1 THEN
            v_json := v_json || ',';
          END IF;
          v_json := v_json || v_data(i);
        END LOOP;
        v_json := v_json || ']';
        
        :result := v_json;
        DBMS_OUTPUT.PUT_LINE('CHUNK_READY');
      END LOOP;
      
      CLOSE v_cursor;
    END;
    """
    
    stream = Stream.resource(
      fn -> {conn, plsql, params ++ [chunk_size], nil} end,
      &fetch_bulk_chunk/1,
      fn _ -> :ok end
    )
    
    {:ok, stream}
  end
  
  @doc """
  ファイルへのエクスポート（Oracle固有の高速エクスポート）
  """
  def export_to_file(conn, sql, params, file_path, opts \\ []) do
    format = Keyword.get(opts, :format, :csv)
    directory = Keyword.get(opts, :oracle_directory, "DATA_PUMP_DIR")
    
    case format do
      :csv -> export_to_csv(conn, sql, params, file_path, directory)
      :json -> export_to_json(conn, sql, params, file_path)
      _ -> {:error, :unsupported_format}
    end
  end
  
  @doc """
  パーティション並列ストリーミング
  """
  def create_parallel_partitioned(connections, table_name, partition_key, opts \\ []) do
    # パーティション情報を取得
    partition_sql = """
    SELECT PARTITION_NAME
    FROM USER_TAB_PARTITIONS
    WHERE TABLE_NAME = UPPER(:1)
    ORDER BY PARTITION_POSITION
    """
    
    case Jamdb.Oracle.query(hd(connections), partition_sql, [table_name]) do
      {:ok, %{rows: partitions}} ->
        # 各パーティションに対してストリームを作成
        streams = partitions
        |> Enum.zip(Stream.cycle(connections))
        |> Enum.map(fn {[partition_name], conn} ->
          sql = "SELECT * FROM #{table_name} PARTITION (#{partition_name})"
          
          case create(conn, sql, [], opts) do
            {:ok, stream} -> stream
            _ -> Stream.empty()
          end
        end)
        
        {:ok, Stream.concat(streams)}
      
      _ ->
        # パーティションがない場合は通常の並列処理
        create_hash_partitioned_streams(connections, table_name, partition_key, opts)
    end
  end
  
  @doc """
  結果キャッシュを使用したストリーミング
  """
  def create_cached_stream(conn, sql, params, opts \\ []) do
    cache_hint = "/*+ RESULT_CACHE */"
    cached_sql = "#{cache_hint} #{sql}"
    
    create(conn, cached_sql, params, opts)
  end
  
  @doc """
  インメモリオプションを使用した高速ストリーミング
  """
  def create_inmemory_stream(conn, table_name, where_clause \\ "", opts \\ []) do
    # Oracle In-Memoryオプションを活用
    sql = """
    SELECT /*+ INMEMORY FULL(t) */ *
    FROM #{table_name} t
    #{if where_clause != "", do: "WHERE " <> where_clause, else: ""}
    """
    
    create(conn, sql, [], opts)
  end
  
  @doc """
  分析関数を使用したウィンドウストリーミング
  """
  def create_windowed_stream(conn, sql, params, window_column, window_size, opts \\ []) do
    chunk_size = Keyword.get(opts, :chunk_size, @default_chunk_size)
    overlap = Keyword.get(opts, :overlap, 0)
    
    windowed_sql = """
    WITH windowed_data AS (
      SELECT 
        t.*,
        FLOOR((ROW_NUMBER() OVER (ORDER BY #{window_column}) - 1) / :window_size) AS window_id
      FROM (#{sql}) t
    )
    SELECT * FROM windowed_data
    ORDER BY window_id, #{window_column}
    """
    
    params_with_window = params ++ [window_size]
    
    # ウィンドウごとにストリーミング
    stream = Stream.resource(
      fn -> {conn, windowed_sql, params_with_window, 0, chunk_size, overlap} end,
      &fetch_window_chunk/1,
      fn _ -> :ok end
    )
    
    {:ok, stream}
  end
  
  @doc """
  XMLType結果のストリーミング
  """
  def create_xml_stream(conn, sql, params, opts \\ []) do
    xml_sql = """
    SELECT XMLELEMENT("row",
      XMLFOREST(t.*)
    ).getClobVal() AS xml_data
    FROM (#{sql}) t
    """
    
    {:ok, stream} = create(conn, xml_sql, params, opts)
    
    # XMLをパースしてマップに変換
    parsed_stream = Stream.map(stream, fn row ->
      parse_xml_to_map(row.xml_data)
    end)
    
    {:ok, parsed_stream}
  end
  
  @doc """
  統計情報付きストリーミング
  """
  def with_stats(conn, sql, params, processor, opts \\ []) do
    # V$SQL_MONITOR を使用して実行統計を取得
    sql_id = generate_sql_id()
    
    monitored_sql = """
    SELECT /*+ MONITOR STATEMENT_ID('#{sql_id}') */ *
    FROM (#{sql})
    """
    
    start_time = System.monotonic_time(:millisecond)
    initial_memory = :erlang.memory(:total)
    
    row_count = 0
    chunk_count = 0
    
    {:ok, stream} = create(conn, monitored_sql, params, opts)
    
    result = stream
    |> Stream.chunk_every(Keyword.get(opts, :chunk_size, @default_chunk_size))
    |> Enum.each(fn chunk ->
      chunk_count = chunk_count + 1
      row_count = row_count + length(chunk)
      Enum.each(chunk, processor)
    end)
    
    end_time = System.monotonic_time(:millisecond)
    final_memory = :erlang.memory(:total)
    
    # Oracle実行統計を取得
    stats_sql = """
    SELECT 
      FETCHES,
      BUFFER_GETS,
      DISK_READS,
      CPU_TIME / 1000 AS cpu_time_ms,
      ELAPSED_TIME / 1000 AS elapsed_time_ms
    FROM V$SQL_MONITOR
    WHERE STATEMENT_ID = :1
    """
    
    oracle_stats = case Jamdb.Oracle.query(conn, stats_sql, [sql_id]) do
      {:ok, %{rows: [[fetches, buffer_gets, disk_reads, cpu_time, elapsed_time]]}} ->
        %{
          fetches: fetches,
          buffer_gets: buffer_gets,
          disk_reads: disk_reads,
          cpu_time_ms: cpu_time,
          elapsed_time_ms: elapsed_time
        }
      _ ->
        %{}
    end
    
    stats = Map.merge(%{
      row_count: row_count,
      chunk_count: chunk_count,
      duration_ms: end_time - start_time,
      memory_used: final_memory - initial_memory,
      rows_per_second: if row_count > 0 do
        row_count / ((end_time - start_time) / 1000)
      else
        0
      end
    }, oracle_stats)
    
    {result, stats}
  end
  
  # プライベート関数
  
  defp execute_with_cursor(conn, sql, params) do
    # REF CURSORの実行
    case Jamdb.Oracle.query(conn, sql, params ++ [{:out, :cursor}]) do
      {:ok, %{out_params: [cursor]}} -> {:ok, cursor}
      error -> error
    end
  end
  
  defp create_cursor_stream(conn, cursor, chunk_size) do
    Stream.resource(
      fn -> {conn, cursor, chunk_size} end,
      &fetch_cursor_chunk/1,
      fn {_conn, cursor, _} ->
        # カーソルのクローズ
        close_cursor(cursor)
      end
    )
  end
  
  defp fetch_cursor_chunk({conn, cursor, chunk_size}) do
    case fetch_from_cursor(conn, cursor, chunk_size) do
      {:ok, []} -> 
        {:halt, {conn, cursor, chunk_size}}
      
      {:ok, rows} ->
        {rows, {conn, cursor, chunk_size}}
      
      {:error, _} ->
        {:halt, {conn, cursor, chunk_size}}
    end
  end
  
  defp fetch_from_cursor(conn, cursor, limit) do
    # カーソルからデータをフェッチ
    # jamdb_oracleの実装に依存
    # 実際の実装はドライバーのAPIに合わせて調整が必要
    try do
      {:ok, Jamdb.Oracle.fetch(cursor, limit)}
    rescue
      _ -> {:error, :fetch_failed}
    end
  end
  
  defp close_cursor(cursor) do
    # カーソルのクローズ処理
    # jamdb_oracleの実装に依存
    :ok
  end
  
  defp fetch_bulk_chunk({conn, plsql, params, buffer}) do
    # BULK COLLECTの結果を取得
    case Jamdb.Oracle.query(conn, plsql, params ++ [{:out, :clob}]) do
      {:ok, %{out_params: [json_data]}} when json_data != nil ->
        rows = Jason.decode!(json_data)
        {rows, {conn, plsql, params, nil}}
      
      _ ->
        {:halt, {conn, plsql, params, buffer}}
    end
  end
  
  defp export_to_csv(conn, sql, params, file_path, directory) do
    # Oracle UTL_FILEを使用したCSVエクスポート
    plsql = """
    DECLARE
      v_file UTL_FILE.FILE_TYPE;
      v_cursor SYS_REFCURSOR;
      v_line VARCHAR2(32767);
    BEGIN
      v_file := UTL_FILE.FOPEN(:directory, :filename, 'W', 32767);
      
      OPEN v_cursor FOR #{sql};
      
      LOOP
        FETCH v_cursor INTO v_line;
        EXIT WHEN v_cursor%NOTFOUND;
        UTL_FILE.PUT_LINE(v_file, v_line);
      END LOOP;
      
      CLOSE v_cursor;
      UTL_FILE.FCLOSE(v_file);
      
      :row_count := v_cursor%ROWCOUNT;
    END;
    """
    
    filename = Path.basename(file_path)
    
    case Jamdb.Oracle.query(conn, plsql, [directory, filename] ++ params ++ [{:out, :integer}]) do
      {:ok, %{out_params: [count]}} -> {:ok, count}
      error -> error
    end
  end
  
  defp export_to_json(conn, sql, params, file_path) do
    # JSON形式でエクスポート
    json_sql = """
    SELECT JSON_ARRAYAGG(
      JSON_OBJECT(*) RETURNING CLOB
    ) AS json_data
    FROM (#{sql})
    """
    
    case Jamdb.Oracle.query(conn, json_sql, params) do
      {:ok, %{rows: [[json_data]]}} ->
        File.write!(file_path, json_data)
        
        # 行数を取得
        count_sql = "SELECT COUNT(*) FROM (#{sql})"
        case Jamdb.Oracle.query(conn, count_sql, params) do
          {:ok, %{rows: [[count]]}} -> {:ok, count}
          _ -> {:ok, 0}
        end
      
      error -> error
    end
  end
  
  defp create_hash_partitioned_streams(connections, table_name, partition_key, opts) do
    partition_count = length(connections)
    
    streams = connections
    |> Enum.with_index()
    |> Enum.map(fn {conn, index} ->
      # ORA_HASHを使用したパーティション分割
      sql = """
      SELECT *
      FROM #{table_name}
      WHERE MOD(ORA_HASH(#{partition_key}), :1) = :2
      """
      
      case create(conn, sql, [partition_count, index], opts) do
        {:ok, stream} -> stream
        _ -> Stream.empty()
      end
    end)
    
    {:ok, Stream.concat(streams)}
  end
  
  defp fetch_window_chunk({conn, sql, params, current_window, chunk_size, overlap}) do
    # ウィンドウベースのフェッチ
    window_sql = """
    SELECT * FROM (
      #{sql}
    ) WHERE window_id = :current_window
    """
    
    case Jamdb.Oracle.query(conn, window_sql, params ++ [current_window]) do
      {:ok, %{rows: []}} ->
        {:halt, {conn, sql, params, current_window, chunk_size, overlap}}
      
      {:ok, %{rows: rows, columns: columns}} ->
        processed_rows = Enum.map(rows, fn row ->
          columns
          |> Enum.zip(row)
          |> Enum.into(%{})
          |> convert_oracle_types()
        end)
        
        # オーバーラップ処理
        if overlap > 0 do
          # 次のウィンドウから一部のデータを取得
          overlap_sql = """
          SELECT * FROM (
            #{sql}
          ) WHERE window_id = :next_window
          FETCH FIRST :overlap ROWS ONLY
          """
          
          case Jamdb.Oracle.query(conn, overlap_sql, params ++ [current_window + 1, overlap]) do
            {:ok, %{rows: overlap_rows}} when overlap_rows != [] ->
              overlap_processed = Enum.map(overlap_rows, fn row ->
                columns
                |> Enum.zip(row)
                |> Enum.into(%{})
                |> convert_oracle_types()
              end)
              
              {processed_rows ++ overlap_processed, {conn, sql, params, current_window + 1, chunk_size, overlap}}
            
            _ ->
              {processed_rows, {conn, sql, params, current_window + 1, chunk_size, overlap}}
          end
        else
          {processed_rows, {conn, sql, params, current_window + 1, chunk_size, overlap}}
        end
      
      {:error, _} ->
        {:halt, {conn, sql, params, current_window, chunk_size, overlap}}
    end
  end
  
  defp parse_xml_to_map(xml_string) do
    # 簡易的なXMLパース（実際の実装では適切なXMLパーサーを使用）
    # ここでは例として簡単な実装を示す
    %{xml: xml_string}
  end
  
  defp generate_sql_id do
    "YESQL_#{:erlang.unique_integer([:positive])}"
  end
  
  defp convert_oracle_types(row) do
    # Oracle特有の型変換
    Enum.map(row, fn {key, value} ->
      converted_value = case value do
        %{year: _, month: _, day: _} = date ->
          # DATE型の変換
          Date.from_erl!({date.year, date.month, date.day})
        
        %{year: _, month: _, day: _, hour: _, minute: _, second: _} = timestamp ->
          # TIMESTAMP型の変換
          NaiveDateTime.from_erl!(
            {{timestamp.year, timestamp.month, timestamp.day},
             {timestamp.hour, timestamp.minute, timestamp.second}}
          )
        
        {:blob, blob_data} ->
          # BLOBデータの処理
          Base.encode64(blob_data)
        
        {:clob, clob_data} ->
          # CLOBデータの処理
          clob_data
        
        %Decimal{} = decimal ->
          # NUMBER型はDecimalのまま
          decimal
        
        other ->
          other
      end
      
      {key, converted_value}
    end)
    |> Enum.into(%{})
  end
end