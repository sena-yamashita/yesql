if Code.ensure_loaded?(Duckdbex) do
  defmodule Yesql.Stream.DuckDBStream do
    @moduledoc """
    DuckDB用のストリーミング実装

    DuckDBの効率的な分析エンジンを活用して、大規模データセットを
    ストリーミング処理します。
    """

    @doc """
    DuckDB用のストリームを作成

    ## オプション

      * `:chunk_size` - 一度に取得するチャンクサイズ（デフォルト: 1000）
      * `:prefetch` - プリフェッチを有効にするか（デフォルト: true）
      * `:parallel` - 並列処理を有効にするか（デフォルト: false）
    """
    def create(conn, sql, params, opts \\ []) do
      chunk_size = Keyword.get(opts, :chunk_size, 1000)
      prefetch = Keyword.get(opts, :prefetch, true)

      # DuckDBでクエリを実行
      case Duckdbex.query(conn, sql, params) do
        {:ok, result_ref} ->
          # 結果セットのメタデータを取得
          columns = get_columns(result_ref)
          # DuckDBexは行数を事前に取得できないため、:unknownを使用
          total_rows = :unknown

          # ストリームを作成
          stream = create_result_stream(result_ref, columns, chunk_size, total_rows)

          # プリフェッチが有効な場合はバッファリングを追加
          final_stream =
            if prefetch do
              # DuckDBexは一度にすべて取得するため、プリフェッチは不要
              stream
            else
              stream
            end

          {:ok, final_stream}

        error ->
          error
      end
    end

    # Arrow形式は現在のDuckDBexではサポートされていません
    # 将来的な実装のためのプレースホルダー
    @doc false
    def create_arrow_stream(_conn, _sql, _params, _opts \\ []) do
      {:error, "Arrow streaming is not supported in current DuckDBex version"}
    end

    @doc """
    並列ストリーミング（テーブルスキャン用）

    DuckDBの並列スキャン機能を活用して、
    大規模テーブルを高速に処理します。
    """
    def create_parallel_scan(conn, table_name, opts \\ []) do
      parallelism = Keyword.get(opts, :parallelism, System.schedulers_online())
      chunk_size = Keyword.get(opts, :chunk_size, 5000)
      where_clause = Keyword.get(opts, :where, "")

      # 並列スキャンを初期化
      case init_parallel_scan(conn, table_name, parallelism, where_clause) do
        {:ok, scan_state} ->
          # 各ワーカーのストリームを作成
          worker_streams =
            Enum.map(1..parallelism, fn worker_id ->
              create_worker_stream(conn, scan_state, worker_id, chunk_size)
            end)

          # ストリームをマージ
          merged_stream = merge_streams(worker_streams)

          {:ok, merged_stream}

        error ->
          error
      end
    end

    @doc """
    集約クエリのストリーミング

    GROUP BYやウィンドウ関数を含むクエリを
    効率的にストリーミング処理します。
    """
    def create_aggregation_stream(conn, sql, params, opts \\ []) do
      chunk_size = Keyword.get(opts, :chunk_size, 1000)
      materialize = Keyword.get(opts, :materialize, true)

      # 集約クエリを最適化
      _optimized_sql =
        if materialize do
          # 一時テーブルにマテリアライズ
          temp_table = "temp_stream_#{:erlang.unique_integer([:positive])}"
          create_sql = "CREATE TEMP TABLE #{temp_table} AS #{sql}"

          case Duckdbex.query(conn, create_sql, params) do
            {:ok, _} ->
              # 一時テーブルからストリーミング
              create(conn, "SELECT * FROM #{temp_table}", [], chunk_size: chunk_size)

            error ->
              error
          end
        else
          # 直接ストリーミング
          create(conn, sql, params, chunk_size: chunk_size)
        end
    end

    @doc """
    Parquetファイルへのストリーミングエクスポート

    大規模データセットを効率的にParquet形式で保存します。
    """
    def export_to_parquet(conn, sql, params, file_path, opts \\ []) do
      compression = Keyword.get(opts, :compression, :snappy)
      row_group_size = Keyword.get(opts, :row_group_size, 100_000)

      # DuckDBのCOPY TO機能を使用
      export_sql = """
      COPY (#{sql}) TO '#{file_path}' 
      WITH (FORMAT PARQUET, COMPRESSION '#{compression}', ROW_GROUP_SIZE #{row_group_size})
      """

      case Duckdbex.query(conn, export_sql, params) do
        {:ok, _} -> {:ok, file_path}
        error -> error
      end
    end

    @doc """
    ウィンドウ付きストリーミング

    時系列データなどで、ウィンドウごとにデータを処理します。
    """
    def create_windowed_stream(conn, sql, params, window_column, window_size, opts \\ []) do
      _overlap = Keyword.get(opts, :overlap, 0)

      # ウィンドウクエリを生成
      windowed_sql = """
      WITH windowed AS (
        SELECT *,
          FLOOR(EXTRACT(EPOCH FROM #{window_column}) / #{window_size}) as window_id
        FROM (#{sql}) base
      )
      SELECT * FROM windowed
      ORDER BY window_id, #{window_column}
      """

      case create(conn, windowed_sql, params, opts) do
        {:ok, stream} ->
          # ウィンドウごとにグループ化
          windowed_stream =
            stream
            |> Stream.chunk_by(fn row -> row[:window_id] end)
            |> Stream.map(fn window ->
              %{
                window_id: hd(window).window_id,
                start_time: calculate_window_start(hd(window).window_id, window_size),
                end_time: calculate_window_end(hd(window).window_id, window_size),
                data: window
              }
            end)

          {:ok, windowed_stream}

        error ->
          error
      end
    end

    # プライベート関数

    defp create_result_stream(result_ref, columns, _chunk_size, _total_rows) do
      # DuckDBexはfetch_chunkで2048行ずつのチャンクを返す
      # Stream.resourceを使って真のストリーミングを実装
      Stream.resource(
        fn -> result_ref end,
        fn result_ref ->
          # DuckDBexから次のチャンクを取得
          case Duckdbex.fetch_chunk(result_ref) do
            [] ->
              {:halt, result_ref}

            rows ->
              # 行をマップに変換
              mapped_rows =
                Enum.map(rows, fn row ->
                  columns
                  |> Enum.zip(row)
                  |> Enum.into(%{})
                end)

              # チャンク内の行を返す
              {mapped_rows, result_ref}
          end
        end,
        fn _result_ref -> :ok end
      )
    end

    defp get_columns(result_ref) do
      # Duckdbex.columnsは直接カラム名のリストを返す
      case Duckdbex.columns(result_ref) do
        columns when is_list(columns) ->
          Enum.map(columns, fn
            col when is_atom(col) -> col
            col when is_binary(col) -> String.to_atom(col)
            _ -> :unknown
          end)

        _ ->
          []
      end
    end

    defp init_parallel_scan(conn, table_name, parallelism, where_clause) do
      # 並列スキャンの初期化
      sql =
        if where_clause != "" do
          "SELECT * FROM #{table_name} WHERE #{where_clause}"
        else
          "SELECT * FROM #{table_name}"
        end

      # テーブルのサイズを取得
      count_sql = "SELECT COUNT(*) as count FROM #{table_name}"

      case Duckdbex.query(conn, count_sql, []) do
        {:ok, result} ->
          [[count]] = Duckdbex.fetch_all(result)
          rows_per_worker = div(count, parallelism)

          {:ok,
           %{
             table: table_name,
             total_rows: count,
             rows_per_worker: rows_per_worker,
             sql: sql
           }}

        error ->
          error
      end
    end

    defp create_worker_stream(conn, scan_state, worker_id, chunk_size) do
      offset = (worker_id - 1) * scan_state.rows_per_worker
      limit = scan_state.rows_per_worker

      # ワーカー用のSQL
      worker_sql = """
      #{scan_state.sql}
      LIMIT #{limit} OFFSET #{offset}
      """

      case create(conn, worker_sql, [], chunk_size: chunk_size) do
        {:ok, stream} -> stream
        _ -> Stream.unfold(nil, fn _ -> nil end)
      end
    end

    defp merge_streams(streams) do
      # ラウンドロビンでストリームをマージ
      Stream.resource(
        fn -> {streams, 0} end,
        fn {streams, index} ->
          if streams == [] do
            {:halt, nil}
          else
            current_stream = Enum.at(streams, rem(index, length(streams)))

            case Enum.take(current_stream, 1) do
              [] ->
                # このストリームは終了
                remaining = List.delete(streams, current_stream)

                if remaining == [] do
                  {:halt, nil}
                else
                  {[], {remaining, index}}
                end

              [item] ->
                {[item], {streams, index + 1}}
            end
          end
        end,
        fn _ -> :ok end
      )
    end

    defp calculate_window_start(window_id, window_size) do
      DateTime.from_unix!(round(window_id * window_size))
    end

    defp calculate_window_end(window_id, window_size) do
      DateTime.from_unix!(round((window_id + 1) * window_size))
    end
  end
end
