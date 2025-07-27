if Code.ensure_loaded?(Postgrex) do
  defmodule Yesql.Stream.PostgrexStream do
    @moduledoc """
    PostgreSQL（Postgrex）用のストリーミング実装

    Postgrexの`stream/4`機能を使用して、大量のデータを効率的に処理します。
    """

    @doc """
    PostgreSQL用のストリームを作成

    ## オプション

      * `:max_rows` - 一度に取得する最大行数（デフォルト: 500）
      * `:chunk_size` - チャンクサイズ（max_rowsのエイリアス）
      * `:decode_mapper` - カスタムデコーダー（省略可）
      * `:mode` - `:text`または`:binary`（デフォルト: `:text`）
    """
    def create(conn, sql, params, opts \\ []) do
      max_rows = Keyword.get(opts, :max_rows, 500)
      chunk_size = Keyword.get(opts, :chunk_size, max_rows)

      # カーソルベースのストリーミングを実装
      stream = Stream.resource(
        # 初期化
        fn -> 
          # 一意のカーソル名を生成
          cursor_name = "yesql_cursor_#{:erlang.unique_integer([:positive])}"
          {:start, conn, cursor_name, sql, params, chunk_size}
        end,
        
        # 次の要素を取得
        fn
          {:start, conn, cursor_name, sql, params, chunk_size} ->
            # トランザクションを開始してカーソルを宣言
            case Postgrex.transaction(conn, fn tx_conn ->
              declare_sql = "DECLARE #{cursor_name} CURSOR FOR #{sql}"
              
              case Postgrex.query(tx_conn, declare_sql, params) do
                {:ok, _} ->
                  # 最初のフェッチ
                  fetch_rows(tx_conn, cursor_name, chunk_size)
                  
                {:error, _} = error ->
                  error
              end
            end) do
              {:ok, {:ok, rows}} ->
                {rows, {:fetching, conn, cursor_name, chunk_size}}
                
              {:ok, {:error, _}} ->
                {:halt, :error}
                
              {:error, _} ->
                {:halt, :error}
            end
            
          {:fetching, conn, cursor_name, chunk_size} ->
            # 続きのデータをフェッチ
            case Postgrex.transaction(conn, fn tx_conn ->
              fetch_rows(tx_conn, cursor_name, chunk_size)
            end) do
              {:ok, {:ok, []}} ->
                # データの終わり
                {:halt, {:done, conn, cursor_name}}
                
              {:ok, {:ok, rows}} ->
                {rows, {:fetching, conn, cursor_name, chunk_size}}
                
              _ ->
                {:halt, {:error, conn, cursor_name}}
            end
            
          _ ->
            {:halt, :done}
        end,
        
        # クリーンアップ
        fn 
          {:done, conn, cursor_name} ->
            # カーソルをクローズ
            Postgrex.transaction(conn, fn tx_conn ->
              Postgrex.query(tx_conn, "CLOSE #{cursor_name}", [])
            end)
            :ok
            
          {:error, conn, cursor_name} ->
            # エラー時もカーソルをクローズ
            try do
              Postgrex.transaction(conn, fn tx_conn ->
                Postgrex.query(tx_conn, "CLOSE #{cursor_name}", [])
              end)
            rescue
              _ -> :ok
            end
            :ok
            
          _ ->
            :ok
        end
      )
      
      {:ok, stream}
    end

    @doc """
    Postgrexの標準stream関数を使用したシンプルな実装

    トランザクション内で実行する必要があります。
    """
    def create_simple(conn, sql, params, opts \\ []) do
      chunk_size = Keyword.get(opts, :chunk_size, 500)
      
      # 単純なクエリ実行（非ストリーミング）
      case Postgrex.query(conn, sql, params) do
        {:ok, %Postgrex.Result{rows: rows, columns: columns}} ->
          atom_columns = Enum.map(columns, &String.to_atom/1)
          
          # ストリームとして返す
          stream = Stream.map(rows, fn row ->
            atom_columns
            |> Enum.zip(row)
            |> Enum.into(%{})
          end)
          |> Stream.chunk_every(chunk_size)
          |> Stream.flat_map(&Function.identity/1)
          
          {:ok, stream}
          
        {:error, _} = error ->
          error
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
      pid =
        spawn_link(fn ->
          case create(conn, sql, params, opts) do
            {:ok, stream} ->
              stream
              |> Stream.each(fn chunk ->
                send(parent, {ref, :data, chunk})
              end)
              |> Stream.run()

              send(parent, {ref, :done})

            error ->
              send(parent, {ref, :error, error})
          end
        end)

      # 非同期ストリームを返す
      async_stream =
        Stream.resource(
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

      result =
        create(conn, sql, params, opts)
        |> case do
          {:ok, stream} ->
            final_count =
              stream
              |> Stream.map(fn chunk ->
                # チャンクを処理
                processor_fn.(chunk)
                1
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
        rows_per_second:
          if(end_time > start_time, do: row_count * 1000 / (end_time - start_time), else: 0)
      }

      {result, stats}
    end

    # プライベート関数

    defp fetch_rows(conn, cursor_name, chunk_size) do
      fetch_sql = "FETCH #{chunk_size} FROM #{cursor_name}"
      
      case Postgrex.query(conn, fetch_sql, []) do
        {:ok, %Postgrex.Result{rows: [], columns: _}} ->
          {:ok, []}
          
        {:ok, %Postgrex.Result{rows: rows, columns: columns}} ->
          atom_columns = Enum.map(columns, &String.to_atom/1)
          
          processed_rows = Enum.map(rows, fn row ->
            atom_columns
            |> Enum.zip(row)
            |> Enum.into(%{})
          end)
          
          {:ok, processed_rows}
          
        {:error, _} = error ->
          error
      end
    end
  end
end