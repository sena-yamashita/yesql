if Code.ensure_loaded?(Exqlite) do
  # Exqliteモジュールが存在しない場合のダミー定義
  unless Code.ensure_loaded?(Exqlite.Sqlite3) do
    defmodule Exqlite.Sqlite3 do
      def prepare(_conn, _sql), do: {:error, :not_implemented}
      def bind(_stmt, _params), do: :ok
      def columns(_conn, _stmt), do: {:ok, []}
      def step(_conn, _stmt), do: :done
      def release(_conn, _stmt), do: :ok
      def reset(_stmt), do: :ok
      def open(_path), do: {:ok, nil}
      def close(_conn), do: :ok
      def execute(_conn, _sql), do: :ok
    end
  end
  
  defmodule Yesql.Stream.SQLiteStream do
    @moduledoc """
    SQLite用のストリーミング実装
    
    SQLiteのステップ実行機能を使用して、メモリ効率的にデータを処理します。
    組み込みデータベースの特性を活かした高速ストリーミングを提供します。
    """
    
    # alias Yesql.Driver  # 未使用のため一時的にコメントアウト
  
  @doc """
  SQLite用のストリームを作成
  
  ## オプション
  
    * `:chunk_size` - 一度に取得するチャンクサイズ（デフォルト: 100）
    * `:cache_size` - SQLiteのキャッシュサイズ（ページ数）
    * `:journal_mode` - ジャーナルモード（:wal, :delete, :memory）
  """
  def create(conn, sql, params, opts \\ []) do
    chunk_size = Keyword.get(opts, :chunk_size, 100)
    
    # SQLiteのプリペアドステートメントを作成
    case Exqlite.Sqlite3.prepare(conn, sql) do
      {:ok, statement} ->
        # パラメータをバインド
        bind_params(conn, statement, params)
        
        # カラム情報を取得
        columns = get_columns(conn, statement)
        
        # ストリームを作成
        stream = create_step_stream(conn, statement, columns, chunk_size)
        
        {:ok, stream}
        
      error ->
        error
    end
  end
  
  @doc """
  メモリ効率最適化されたストリーミング
  
  大規模データセットに対して、メモリ使用量を最小限に抑えながら処理します。
  """
  def create_memory_optimized(conn, sql, params, opts \\ []) do
    # メモリ最適化設定
    optimize_for_streaming(conn)
    
    # 通常のストリーミングを使用
    create(conn, sql, params, opts)
  end
  
  @doc """
  インデックスを活用した高速ストリーミング
  
  SQLiteのインデックスを最大限活用して、高速なデータアクセスを実現します。
  """
  def create_indexed_stream(conn, table, index_column, opts \\ []) do
    start_value = Keyword.get(opts, :start_value)
    end_value = Keyword.get(opts, :end_value)
    chunk_size = Keyword.get(opts, :chunk_size, 1000)
    
    # インデックスを使用したクエリを生成
    sql = build_indexed_query(table, index_column, start_value, end_value)
    
    # 分析情報を取得
    analyze_query(conn, sql)
    
    # ストリーミング実行
    create(conn, sql, [], chunk_size: chunk_size)
  end
  
  @doc """
  全文検索（FTS5）のストリーミング
  
  SQLiteのFTS5機能を使用した全文検索結果をストリーミングします。
  """
  def create_fts_stream(conn, fts_table, search_query, opts \\ []) do
    chunk_size = Keyword.get(opts, :chunk_size, 100)
    rank_order = Keyword.get(opts, :rank_order, true)
    
    # FTS5クエリを構築
    sql = if rank_order do
      """
      SELECT *, rank FROM #{fts_table}
      WHERE #{fts_table} MATCH ?
      ORDER BY rank
      """
    else
      """
      SELECT * FROM #{fts_table}
      WHERE #{fts_table} MATCH ?
      """
    end
    
    create(conn, sql, [search_query], chunk_size: chunk_size)
  end
  
  @doc """
  JSON データのストリーミング
  
  SQLiteのJSON関数を使用してJSONデータを効率的に処理します。
  """
  def create_json_stream(conn, table, json_column, json_path, opts \\ []) do
    chunk_size = Keyword.get(opts, :chunk_size, 100)
    filter = Keyword.get(opts, :filter)
    
    # JSON抽出クエリを構築
    sql = """
    SELECT 
      *,
      json_extract(#{json_column}, '#{json_path}') as extracted_value
    FROM #{table}
    #{if filter, do: "WHERE json_extract(#{json_column}, '#{json_path}') #{filter}", else: ""}
    """
    
    create(conn, sql, [], chunk_size: chunk_size)
  end
  
  @doc """
  バッチ挿入のストリーミング
  
  大量のデータを効率的にSQLiteに挿入します。
  """
  def stream_insert(conn, table, columns, data_stream, opts \\ []) do
    batch_size = Keyword.get(opts, :batch_size, 1000)
    use_transaction = Keyword.get(opts, :use_transaction, true)
    
    # プレースホルダーを生成
    placeholders = Enum.map(1..length(columns), fn _ -> "?" end) |> Enum.join(", ")
    insert_sql = "INSERT INTO #{table} (#{Enum.join(columns, ", ")}) VALUES (#{placeholders})"
    
    # トランザクション開始
    if use_transaction do
      Exqlite.Sqlite3.execute(conn, "BEGIN IMMEDIATE")
    end
    
    try do
      # プリペアドステートメントを作成
      {:ok, statement} = Exqlite.Sqlite3.prepare(conn, insert_sql)
      
      # バッチごとに挿入
      count = data_stream
      |> Stream.chunk_every(batch_size)
      |> Stream.map(fn batch ->
        insert_batch(conn, statement, batch)
        length(batch)
      end)
      |> Enum.sum()
      
      # コミット
      if use_transaction do
        Exqlite.Sqlite3.execute(conn, "COMMIT")
      end
      
      {:ok, count}
    rescue
      error ->
        if use_transaction do
          Exqlite.Sqlite3.execute(conn, "ROLLBACK")
        end
        {:error, error}
    end
  end
  
  @doc """
  WALモードでの並列読み取り
  
  Write-Ahead Loggingモードで複数の読み取りを並列実行します。
  """
  def create_parallel_wal_streams(db_path, queries, opts \\ []) do
    parallelism = length(queries)
    
    # 各クエリ用の接続を作成
    connections = Enum.map(1..parallelism, fn _ ->
      {:ok, conn} = Exqlite.Sqlite3.open(db_path)
      
      # WALモードを設定
      Exqlite.Sqlite3.execute(conn, "PRAGMA journal_mode = WAL")
      Exqlite.Sqlite3.execute(conn, "PRAGMA synchronous = NORMAL")
      
      conn
    end)
    
    # 各接続でストリームを作成
    streams = queries
    |> Enum.zip(connections)
    |> Enum.map(fn {{sql, params}, conn} ->
      Task.async(fn ->
        create(conn, sql, params, opts)
      end)
    end)
    |> Enum.map(&Task.await/1)
    
    # クリーンアップ関数を含めて返す
    cleanup_fn = fn ->
      Enum.each(connections, &Exqlite.Sqlite3.close/1)
    end
    
    {streams, cleanup_fn}
  end
  
  # プライベート関数
  
  defp create_step_stream(conn, statement, columns, chunk_size) do
    Stream.resource(
      fn -> {conn, statement, columns, []} end,
      fn {conn, statement, columns, buffer} ->
        if buffer == [] do
          # 新しいチャンクを取得
          rows = fetch_chunk(conn, statement, chunk_size, [])
          
          if rows == [] do
            {:halt, statement}
          else
            # 行をマップに変換
            processed_rows = Enum.map(rows, fn row ->
              columns
              |> Enum.zip(row)
              |> Enum.into(%{})
            end)
            
            {processed_rows, {conn, statement, columns, []}}
          end
        else
          {buffer, {conn, statement, columns, []}}
        end
      end,
      fn statement ->
        Exqlite.Sqlite3.release(conn, statement)
      end
    )
  end
  
  defp fetch_chunk(_conn, _statement, 0, acc), do: Enum.reverse(acc)
  defp fetch_chunk(conn, statement, remaining, acc) do
    case Exqlite.Sqlite3.step(conn, statement) do
      :done -> 
        Enum.reverse(acc)
        
      {:row, row} -> 
        fetch_chunk(conn, statement, remaining - 1, [row | acc])
        
      {:error, _reason} -> 
        Enum.reverse(acc)
    end
  end
  
  defp bind_params(_conn, _statement, []), do: :ok
  defp bind_params(_conn, statement, params) do
    Exqlite.Sqlite3.bind(statement, params)
  end
  
  defp get_columns(conn, statement) do
    case Exqlite.Sqlite3.columns(conn, statement) do
      {:ok, columns} -> 
        Enum.map(columns, &String.to_atom/1)
      _ -> 
        []
    end
  end
  
  defp optimize_for_streaming(conn) do
    # ストリーミング用の最適化設定
    optimizations = [
      "PRAGMA cache_size = -64000",        # 64MBのキャッシュ
      "PRAGMA temp_store = MEMORY",        # 一時ストレージをメモリに
      "PRAGMA mmap_size = 268435456",      # 256MBのメモリマップ
      "PRAGMA page_size = 4096",           # ページサイズを4KB
      "PRAGMA synchronous = OFF",          # 同期をオフ（読み取り専用時）
      "PRAGMA journal_mode = WAL",         # WALモード
      "PRAGMA wal_autocheckpoint = 10000"  # WALチェックポイント
    ]
    
    Enum.each(optimizations, fn pragma ->
      Exqlite.Sqlite3.execute(conn, pragma)
    end)
  end
  
  defp build_indexed_query(table, index_column, start_value, end_value) do
    base_query = "SELECT * FROM #{table}"
    
    where_clauses = []
    where_clauses = if start_value, do: ["#{index_column} >= '#{start_value}'"] ++ where_clauses, else: where_clauses
    where_clauses = if end_value, do: ["#{index_column} <= '#{end_value}'"] ++ where_clauses, else: where_clauses
    
    if where_clauses != [] do
      base_query <> " WHERE " <> Enum.join(where_clauses, " AND ") <> " ORDER BY #{index_column}"
    else
      base_query <> " ORDER BY #{index_column}"
    end
  end
  
  defp analyze_query(conn, sql) do
    # クエリプランを分析
    explain_sql = "EXPLAIN QUERY PLAN #{sql}"
    
    case Exqlite.Sqlite3.prepare(conn, explain_sql) do
      {:ok, statement} ->
        plan = fetch_all_rows(conn, statement, [])
        Exqlite.Sqlite3.release(conn, statement)
        
        # インデックス使用を確認
        uses_index = Enum.any?(plan, fn row ->
          row_string = Enum.join(Tuple.to_list(row), " ")
          String.contains?(row_string, "USING INDEX")
        end)
        
        if not uses_index do
          IO.warn("Query does not use index. Consider creating an index for better performance.")
        end
        
      _ ->
        :ok
    end
  end
  
  defp fetch_all_rows(conn, statement, acc) do
    case Exqlite.Sqlite3.step(conn, statement) do
      :done -> Enum.reverse(acc)
      {:row, row} -> fetch_all_rows(conn, statement, [row | acc])
      _ -> Enum.reverse(acc)
    end
  end
  
  defp insert_batch(conn, statement, batch) do
    Enum.each(batch, fn row_data ->
      # ステートメントをリセット
      Exqlite.Sqlite3.reset(statement)
      
      # データをバインド
      values = if is_map(row_data), do: Map.values(row_data), else: row_data
      Exqlite.Sqlite3.bind(statement, values)
      
      # 実行
      case Exqlite.Sqlite3.step(conn, statement) do
        :done -> :ok
        error -> throw(error)
      end
    end)
  end
  end
end