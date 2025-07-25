defmodule Yesql.Stream do
  @moduledoc """
  ストリーミング結果セットのサポートモジュール
  
  大量のデータを扱う際にメモリ効率的にデータを処理するための機能を提供します。
  各データベースドライバーに対して統一的なストリーミングインターフェースを提供します。
  """
  
  alias Yesql.{Driver, DriverFactory}
  
  @doc """
  ストリーミングクエリを実行し、Streamを返す
  
  ## パラメータ
  
    * `conn` - データベース接続
    * `sql` - 実行するSQL
    * `params` - クエリパラメータ
    * `opts` - オプション
      * `:driver` - 使用するドライバー（必須）
      * `:chunk_size` - 一度に取得する行数（デフォルト: 1000）
      * `:timeout` - クエリタイムアウト（ミリ秒）
      * `:max_rows` - 最大行数の制限
  
  ## 戻り値
  
    * `{:ok, stream}` - Elixir Streamオブジェクト
    * `{:error, reason}` - エラーの場合
  
  ## 例
  
      {:ok, stream} = Yesql.Stream.query(conn, 
        "SELECT * FROM large_table WHERE created_at > $1",
        [~D[2024-01-01]],
        driver: :postgrex,
        chunk_size: 5000
      )
      
      # ストリームを処理
      stream
      |> Stream.map(&process_row/1)
      |> Stream.filter(&valid?/1)
      |> Enum.take(100)
  """
  def query(conn, sql, params, opts) do
    driver_name = Keyword.fetch!(opts, :driver)
    chunk_size = Keyword.get(opts, :chunk_size, 1000)
    
    with {:ok, driver} <- DriverFactory.create(driver_name) do
      if supports_streaming?(driver) do
        create_stream(driver, conn, sql, params, chunk_size, opts)
      else
        {:error, :streaming_not_supported}
      end
    end
  end
  
  @doc """
  ストリーミングクエリを使用してデータを処理する
  
  大量のデータに対して変換処理を適用し、結果を効率的に処理します。
  
  ## 例
  
      # CSVファイルへのエクスポート
      {:ok, count} = Yesql.Stream.process(conn,
        "SELECT * FROM users WHERE status = $1",
        ["active"],
        fn row ->
          csv_line = [row.id, row.name, row.email] |> Enum.join(",")
          File.write!("users.csv", csv_line <> "\n", [:append])
        end,
        driver: :postgrex,
        chunk_size: 10000
      )
  """
  def process(conn, sql, params, processor_fn, opts) when is_function(processor_fn, 1) do
    case query(conn, sql, params, opts) do
      {:ok, stream} ->
        count = stream
        |> Stream.map(fn row ->
          processor_fn.(row)
          1
        end)
        |> Enum.sum()
        
        {:ok, count}
        
      error ->
        error
    end
  end
  
  @doc """
  ストリーミングクエリでデータを集約する
  
  ## 例
  
      # 売上合計を計算（メモリ効率的）
      {:ok, total} = Yesql.Stream.reduce(conn,
        "SELECT amount FROM sales WHERE year = $1",
        [2024],
        0,
        fn row, acc -> acc + row.amount end,
        driver: :mysql
      )
  """
  def reduce(conn, sql, params, initial, reducer_fn, opts) when is_function(reducer_fn, 2) do
    case query(conn, sql, params, opts) do
      {:ok, stream} ->
        result = stream
        |> Enum.reduce(initial, reducer_fn)
        
        {:ok, result}
        
      error ->
        error
    end
  end
  
  @doc """
  ストリーミングでバッチ処理を実行
  
  データを指定されたバッチサイズごとに処理します。
  
  ## 例
  
      {:ok, batch_count} = Yesql.Stream.batch_process(conn,
        "SELECT * FROM logs WHERE level = $1",
        ["error"],
        1000,  # バッチサイズ
        fn batch ->
          # バッチごとに処理
          BulkProcessor.process(batch)
        end,
        driver: :postgrex
      )
  """
  def batch_process(conn, sql, params, batch_size, batch_fn, opts) when is_function(batch_fn, 1) do
    case query(conn, sql, params, opts) do
      {:ok, stream} ->
        batch_count = stream
        |> Stream.chunk_every(batch_size)
        |> Stream.map(fn batch ->
          batch_fn.(batch)
          1
        end)
        |> Enum.sum()
        
        {:ok, batch_count}
        
      error ->
        error
    end
  end
  
  # プライベート関数
  
  defp supports_streaming?(%Yesql.Driver.Postgrex{}), do: true
  defp supports_streaming?(%Yesql.Driver.MySQL{}), do: true
  defp supports_streaming?(%Yesql.Driver.DuckDB{}), do: true
  defp supports_streaming?(%Yesql.Driver.SQLite{}), do: true
  defp supports_streaming?(%Yesql.Driver.MSSQL{}), do: true
  defp supports_streaming?(%Yesql.Driver.Oracle{}), do: true
  defp supports_streaming?(_), do: false
  
  defp create_stream(%Yesql.Driver.Postgrex{} = driver, conn, sql, params, chunk_size, opts) do
    # PostgreSQLのストリーミング実装
    stream = Stream.resource(
      # 初期化
      fn ->
        case Postgrex.stream(conn, sql, params, max_rows: chunk_size) do
          %Postgrex.Stream{} = stream -> stream
          error -> throw({:error, error})
        end
      end,
      
      # 次のチャンクを取得
      fn stream ->
        case Postgrex.Stream.next(stream) do
          {:ok, %{rows: rows}} when rows != [] ->
            # ドライバーのprocess_resultを使って結果を変換
            {:ok, processed} = Driver.process_result(driver, {:ok, %{rows: rows, columns: stream.columns}})
            {processed, stream}
            
          _ ->
            {:halt, stream}
        end
      end,
      
      # クリーンアップ
      fn stream ->
        Postgrex.Stream.close(stream)
      end
    )
    
    {:ok, stream}
  rescue
    e -> {:error, e}
  end
  
  defp create_stream(%Yesql.Driver.MySQL{} = driver, conn, sql, params, chunk_size, opts) do
    # MySQLのストリーミング実装
    stream = Stream.resource(
      # 初期化
      fn ->
        # MyXQLはストリーミングをquery_manyで実現
        ref = make_ref()
        Task.async(fn ->
          MyXQL.stream(conn, sql, params, max_rows: chunk_size)
        end)
      end,
      
      # 次のチャンクを取得
      fn task ->
        case Task.yield(task, 100) || Task.shutdown(task) do
          {:ok, %MyXQL.Stream{} = myxql_stream} ->
            myxql_stream
            |> Stream.flat_map(fn %{rows: rows, columns: columns} ->
              {:ok, processed} = Driver.process_result(driver, {:ok, %{rows: rows, columns: columns}})
              processed
            end)
            |> Enum.to_list()
            |> case do
              [] -> {:halt, task}
              rows -> {rows, task}
            end
            
          _ ->
            {:halt, task}
        end
      end,
      
      # クリーンアップ
      fn _task -> :ok end
    )
    
    {:ok, stream}
  end
  
  defp create_stream(%Yesql.Driver.DuckDB{} = driver, conn, sql, params, chunk_size, opts) do
    # DuckDBのストリーミング実装
    stream = Stream.resource(
      # 初期化
      fn ->
        case Duckdbex.query(conn, sql, params) do
          {:ok, result_ref} -> {result_ref, chunk_size, 0}
          error -> throw({:error, error})
        end
      end,
      
      # 次のチャンクを取得
      fn {result_ref, chunk_size, offset} ->
        case Duckdbex.fetch_chunk(result_ref, offset, chunk_size) do
          {:ok, rows} when rows != [] ->
            columns = Duckdbex.columns(result_ref)
            {:ok, processed} = Driver.process_result(driver, {:ok, %{rows: rows, columns: columns}})
            {processed, {result_ref, chunk_size, offset + length(rows)}}
            
          _ ->
            {:halt, result_ref}
        end
      end,
      
      # クリーンアップ
      fn result_ref ->
        Duckdbex.close_result(result_ref)
      end
    )
    
    {:ok, stream}
  end
  
  defp create_stream(%Yesql.Driver.SQLite{} = driver, conn, sql, params, chunk_size, opts) do
    # SQLiteのストリーミング実装（ステップ実行を使用）
    stream = Stream.resource(
      # 初期化
      fn ->
        case Exqlite.Sqlite3.prepare(conn, sql) do
          {:ok, statement} ->
            :ok = Exqlite.Sqlite3.bind(conn, statement, params)
            columns = Exqlite.Sqlite3.columns(conn, statement)
            {conn, statement, columns, []}
          error ->
            throw({:error, error})
        end
      end,
      
      # 次のチャンクを取得
      fn {conn, statement, columns, buffer} ->
        # バッファが空の場合、新しいデータを取得
        if buffer == [] do
          rows = fetch_sqlite_chunk(conn, statement, chunk_size, [])
          if rows == [] do
            {:halt, {conn, statement}}
          else
            {:ok, processed} = Driver.process_result(driver, {:ok, %{rows: rows, columns: columns}})
            {processed, {conn, statement, columns, []}}
          end
        else
          {buffer, {conn, statement, columns, []}}
        end
      end,
      
      # クリーンアップ
      fn {conn, statement} ->
        Exqlite.Sqlite3.release(conn, statement)
      end
    )
    
    {:ok, stream}
  end
  
  defp create_stream(%Yesql.Driver.MSSQL{} = driver, conn, sql, params, chunk_size, opts) do
    # MSSQLのストリーミング実装
    alias Yesql.Stream.MSSQLStream
    
    case MSSQLStream.create(conn, sql, params, Keyword.put(opts, :chunk_size, chunk_size)) do
      {:ok, stream} -> {:ok, stream}
      error -> error
    end
  end
  
  defp create_stream(%Yesql.Driver.Oracle{} = driver, conn, sql, params, chunk_size, opts) do
    # Oracleのストリーミング実装
    alias Yesql.Stream.OracleStream
    
    case OracleStream.create(conn, sql, params, Keyword.put(opts, :chunk_size, chunk_size)) do
      {:ok, stream} -> {:ok, stream}
      error -> error
    end
  end
  
  defp create_stream(_, _, _, _, _, _) do
    {:error, :streaming_not_implemented}
  end
  
  # SQLite用のヘルパー関数
  defp fetch_sqlite_chunk(conn, statement, 0, acc), do: Enum.reverse(acc)
  defp fetch_sqlite_chunk(conn, statement, remaining, acc) do
    case Exqlite.Sqlite3.step(conn, statement) do
      :done -> Enum.reverse(acc)
      {:row, row} -> fetch_sqlite_chunk(conn, statement, remaining - 1, [row | acc])
      {:error, _} -> Enum.reverse(acc)
    end
  end
end