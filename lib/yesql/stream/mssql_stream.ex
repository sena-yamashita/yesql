if Code.ensure_loaded?(Tds) do
  defmodule Yesql.Stream.MSSQLStream do
    @moduledoc """
    MSSQL（SQL Server）用のストリーミングサポート
    
    TdsドライバーはSQL Serverのカーソル機能をネイティブサポートしていないため、
    以下のアプローチでストリーミングを実装：
    
    1. OFFSET/FETCHを使用したページネーション
    2. 一時テーブルを使用したカーソルエミュレーション
    3. バッチ処理の最適化
    """
    
    alias Yesql.Driver.MSSQLDriver
  
  @default_chunk_size 1000
  @max_batch_size 10000
  
  @doc """
  ストリームを作成する（ページネーションベース）
  """
  def create(conn, sql, params, opts \\ []) do
    chunk_size = Keyword.get(opts, :chunk_size, @default_chunk_size)
    max_rows = Keyword.get(opts, :max_rows)
    
    # SET NOCOUNT ONを追加して余分なメッセージを抑制
    optimized_sql = optimize_sql_for_streaming(sql)
    
    stream = Stream.resource(
      fn -> {conn, optimized_sql, params, 0, chunk_size, max_rows, false} end,
      &fetch_chunk/1,
      fn _ -> :ok end
    )
    
    {:ok, stream}
  rescue
    e -> {:error, e}
  end
  
  @doc """
  カーソルエミュレーションを使用したストリーム
  """
  def create_with_cursor_emulation(conn, sql, params, opts \\ []) do
    chunk_size = Keyword.get(opts, :chunk_size, @default_chunk_size)
    cursor_name = generate_cursor_name()
    
    # 一時テーブルにデータを格納
    setup_sql = """
    SET NOCOUNT ON;
    
    -- 一時テーブルの作成
    CREATE TABLE ##{cursor_name} (
      _row_num BIGINT IDENTITY(1,1) PRIMARY KEY,
      _data NVARCHAR(MAX)
    );
    
    -- データの挿入（JSON形式で保存）
    INSERT INTO ##{cursor_name} (_data)
    SELECT (
      SELECT * FROM (#{sql}) AS _source
      FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    );
    """
    
    case Tds.query(conn, setup_sql, params) do
      {:ok, _} ->
        stream = create_cursor_stream(conn, cursor_name, chunk_size)
        {:ok, stream}
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  @doc """
  ファイルへのエクスポート（BCP形式）
  """
  def export_to_file(conn, sql, params, file_path, opts \\ []) do
    format = Keyword.get(opts, :format, :csv)
    include_headers = Keyword.get(opts, :include_headers, true)
    
    # BCPのような効率的なエクスポートを実装
    export_sql = case format do
      :csv -> build_csv_export_sql(sql, include_headers)
      :tsv -> build_tsv_export_sql(sql, include_headers)
      :json -> build_json_export_sql(sql)
      _ -> {:error, :unsupported_format}
    end
    
    case export_sql do
      {:error, reason} -> {:error, reason}
      sql_query ->
        file = File.open!(file_path, [:write, :utf8])
        
        try do
          {:ok, count} = process_with_chunks(conn, sql_query, params,
            fn chunk ->
              IO.write(file, chunk)
            end,
            Keyword.put(opts, :raw_mode, true)
          )
          
          {:ok, count}
        after
          File.close(file)
        end
    end
  end
  
  @doc """
  並列ストリーミング（パーティション使用）
  """
  def create_parallel_partitioned(connections, table_name, where_clause \\ "", opts \\ []) do
    partition_count = length(connections)
    
    streams = connections
    |> Enum.with_index()
    |> Enum.map(fn {conn, index} ->
      # MODULOを使用したパーティション分割
      partition_sql = """
      SELECT *
      FROM #{table_name} WITH (NOLOCK)
      WHERE (CHECKSUM(NEWID()) % #{partition_count}) = #{index}
      #{if where_clause != "", do: "AND " <> where_clause, else: ""}
      """
      
      case create(conn, partition_sql, [], opts) do
        {:ok, stream} -> stream
        _ -> Stream.empty()
      end
    end)
    
    # 全ストリームを結合
    merged_stream = Stream.concat(streams)
    {:ok, merged_stream}
  end
  
  @doc """
  統計情報付きストリーミング
  """
  def with_stats(conn, sql, params, processor, opts \\ []) do
    start_time = System.monotonic_time(:millisecond)
    initial_memory = :erlang.memory(:total)
    
    row_count = 0
    chunk_count = 0
    
    result = process_with_chunks(conn, sql, params,
      fn chunk ->
        chunk_count = chunk_count + 1
        row_count = row_count + length(chunk)
        
        Enum.each(chunk, processor)
      end,
      opts
    )
    
    end_time = System.monotonic_time(:millisecond)
    final_memory = :erlang.memory(:total)
    
    stats = %{
      row_count: row_count,
      chunk_count: chunk_count,
      duration_ms: end_time - start_time,
      memory_used: final_memory - initial_memory,
      rows_per_second: if row_count > 0 do
        row_count / ((end_time - start_time) / 1000)
      else
        0
      end
    }
    
    {result, stats}
  end
  
  @doc """
  インデックスを活用した高速ストリーミング
  """
  def create_indexed_stream(conn, table_name, index_column, opts \\ []) do
    chunk_size = Keyword.get(opts, :chunk_size, @default_chunk_size)
    start_value = Keyword.get(opts, :start_value)
    end_value = Keyword.get(opts, :end_value)
    
    # インデックスヒントを使用
    sql = """
    SELECT *
    FROM #{table_name} WITH (INDEX(IX_#{index_column}))
    WHERE #{index_column} >= @p1
    #{if end_value, do: "AND #{index_column} <= @p2", else: ""}
    ORDER BY #{index_column}
    """
    
    params = if end_value do
      [start_value || 0, end_value]
    else
      [start_value || 0]
    end
    
    create(conn, sql, params, opts)
  end
  
  @doc """
  一時的な結果セットを使用したストリーミング
  """
  def create_temp_result_stream(conn, sql, params, opts \\ []) do
    temp_table = "#stream_#{:erlang.unique_integer([:positive])}"
    
    # 結果を一時テーブルに格納
    setup_sql = """
    SET NOCOUNT ON;
    
    SELECT *
    INTO #{temp_table}
    FROM (#{sql}) AS _source;
    
    -- インデックスを追加してパフォーマンス向上
    CREATE CLUSTERED INDEX IX_#{temp_table} ON #{temp_table} (
      _row_num
    );
    """
    
    case Tds.query(conn, setup_sql, params) do
      {:ok, _} ->
        # 一時テーブルからストリーミング
        stream_sql = "SELECT * FROM #{temp_table} ORDER BY _row_num"
        stream = create(conn, stream_sql, [], opts)
        
        # クリーンアップ関数を追加
        wrapped_stream = Stream.resource(
          fn -> stream end,
          fn stream ->
            case Stream.take(stream, 1) do
              [] -> {:halt, stream}
              [item] -> {[item], Stream.drop(stream, 1)}
            end
          end,
          fn _ ->
            # 一時テーブルの削除
            Tds.query(conn, "DROP TABLE IF EXISTS #{temp_table}", [])
            :ok
          end
        )
        
        {:ok, wrapped_stream}
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  # プライベート関数
  
  defp fetch_chunk({conn, sql, params, offset, chunk_size, max_rows, done}) when done do
    {:halt, {conn, sql, params, offset, chunk_size, max_rows, done}}
  end
  
  defp fetch_chunk({conn, sql, params, offset, chunk_size, max_rows, done}) do
    # 最大行数のチェック
    fetch_size = case max_rows do
      nil -> chunk_size
      max -> min(chunk_size, max - offset)
    end
    
    if fetch_size <= 0 do
      {:halt, {conn, sql, params, offset, chunk_size, max_rows, true}}
    else
      # OFFSET/FETCHを使用したページネーション
      paginated_sql = """
      #{sql}
      ORDER BY (SELECT NULL)
      OFFSET #{offset} ROWS
      FETCH NEXT #{fetch_size} ROWS ONLY
      """
      
      case Tds.query(conn, paginated_sql, params) do
        {:ok, %{rows: rows, columns: columns}} when rows != [] ->
          # 行をマップに変換
          processed_rows = Enum.map(rows, fn row ->
            columns
            |> Enum.zip(row)
            |> Enum.into(%{})
            |> convert_mssql_types()
          end)
          
          next_offset = offset + length(rows)
          done = length(rows) < fetch_size or (max_rows && next_offset >= max_rows)
          
          {processed_rows, {conn, sql, params, next_offset, chunk_size, max_rows, done}}
        
        {:ok, _} ->
          {:halt, {conn, sql, params, offset, chunk_size, max_rows, true}}
        
        {:error, _reason} ->
          {:halt, {conn, sql, params, offset, chunk_size, max_rows, true}}
      end
    end
  end
  
  defp optimize_sql_for_streaming(sql) do
    """
    SET NOCOUNT ON;
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
    #{sql}
    """
  end
  
  defp generate_cursor_name do
    "cursor_#{:erlang.unique_integer([:positive])}"
  end
  
  defp create_cursor_stream(conn, cursor_name, chunk_size) do
    Stream.resource(
      fn -> {conn, cursor_name, 1, chunk_size, false} end,
      fn {conn, cursor_name, start_row, chunk_size, done} ->
        if done do
          {:halt, {conn, cursor_name, start_row, chunk_size, done}}
        else
          # 一時テーブルから範囲を取得
          sql = """
          SELECT JSON_VALUE(_data, '$') AS data
          FROM ##{cursor_name}
          WHERE _row_num BETWEEN @p1 AND @p2
          ORDER BY _row_num
          """
          
          end_row = start_row + chunk_size - 1
          
          case Tds.query(conn, sql, [start_row, end_row]) do
            {:ok, %{rows: rows}} when rows != [] ->
              # JSONをデコード
              processed_rows = Enum.map(rows, fn [json_data] ->
                Jason.decode!(json_data, keys: :atoms)
              end)
              
              next_start = end_row + 1
              {processed_rows, {conn, cursor_name, next_start, chunk_size, false}}
            
            _ ->
              {:halt, {conn, cursor_name, start_row, chunk_size, true}}
          end
        end
      end,
      fn {conn, cursor_name, _, _, _} ->
        # 一時テーブルの削除
        Tds.query(conn, "DROP TABLE IF EXISTS ##{cursor_name}", [])
        :ok
      end
    )
  end
  
  defp build_csv_export_sql(sql, include_headers) do
    header_sql = if include_headers do
      """
      SELECT STRING_AGG(COLUMN_NAME, ',') AS header
      FROM INFORMATION_SCHEMA.COLUMNS
      WHERE TABLE_NAME = 'temp_export'
      UNION ALL
      """
    else
      ""
    end
    
    """
    WITH temp_export AS (#{sql})
    #{header_sql}
    SELECT STRING_AGG(
      CONCAT_WS(',',
        QUOTENAME(CAST(col1 AS NVARCHAR(MAX)), '"'),
        QUOTENAME(CAST(col2 AS NVARCHAR(MAX)), '"')
      ),
      CHAR(13) + CHAR(10)
    )
    FROM temp_export
    """
  end
  
  defp build_tsv_export_sql(sql, include_headers) do
    # TSV形式のエクスポート
    """
    WITH temp_export AS (#{sql})
    SELECT STRING_AGG(
      REPLACE(CAST((SELECT * FROM temp_export FOR JSON PATH) AS NVARCHAR(MAX)), ',', CHAR(9)),
      CHAR(13) + CHAR(10)
    )
    """
  end
  
  defp build_json_export_sql(sql) do
    """
    SELECT (
      SELECT * FROM (#{sql}) AS data
      FOR JSON PATH
    )
    """
  end
  
  defp process_with_chunks(conn, sql, params, processor, opts) do
    chunk_size = Keyword.get(opts, :chunk_size, @default_chunk_size)
    raw_mode = Keyword.get(opts, :raw_mode, false)
    
    process_chunk_recursive(conn, sql, params, processor, 0, chunk_size, 0, raw_mode)
  end
  
  defp process_chunk_recursive(conn, sql, params, processor, offset, chunk_size, total_count, raw_mode) do
    paginated_sql = """
    #{sql}
    ORDER BY (SELECT NULL)
    OFFSET #{offset} ROWS
    FETCH NEXT #{chunk_size} ROWS ONLY
    """
    
    case Tds.query(conn, paginated_sql, params) do
      {:ok, %{rows: []}} ->
        {:ok, total_count}
      
      {:ok, %{rows: rows} = result} ->
        if raw_mode do
          processor.(rows)
        else
          columns = result.columns
          processed_rows = Enum.map(rows, fn row ->
            columns
            |> Enum.zip(row)
            |> Enum.into(%{})
            |> convert_mssql_types()
          end)
          processor.(processed_rows)
        end
        
        new_count = total_count + length(rows)
        process_chunk_recursive(conn, sql, params, processor, offset + chunk_size, chunk_size, new_count, raw_mode)
      
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp convert_mssql_types(row) do
    # MSSQL特有の型変換
    Enum.map(row, fn {key, value} ->
      converted_value = case value do
        {:ok, datetime} when is_tuple(datetime) ->
          # 日時型の変換
          NaiveDateTime.from_erl!(datetime)
        
        %Decimal{} = decimal ->
          # Decimal型はそのまま
          decimal
        
        binary when is_binary(binary) ->
          # バイナリデータの処理
          case String.valid?(binary) do
            true -> binary
            false -> Base.encode64(binary)
          end
        
        other ->
          other
      end
      
      {key, converted_value}
    end)
    |> Enum.into(%{})
  end
  end
end