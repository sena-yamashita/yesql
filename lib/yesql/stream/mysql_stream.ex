if Code.ensure_loaded?(MyXQL) do
  defmodule Yesql.Stream.MySQLStream do
    @moduledoc """
    MySQL（MyXQL）用のストリーミング実装
    
    MyXQLの`stream/3`機能を使用して、大量のデータを効率的に処理します。
    MySQLのカーソルベースの結果セット取得を活用します。
    """
    
    # alias Yesql.Driver  # 未使用のため一時的にコメントアウト
  
  @doc """
  MySQL用のストリームを作成
  
  ## オプション
  
    * `:max_rows` - 一度に取得する最大行数（デフォルト: 500）
    * `:timeout` - クエリタイムアウト（ミリ秒）
    * `:query_type` - `:text`または`:binary`（デフォルト: `:text`）
  """
  def create(conn, sql, params, opts \\ []) do
    max_rows = Keyword.get(opts, :max_rows, 500)
    timeout = Keyword.get(opts, :timeout, :infinity)
    query_type = Keyword.get(opts, :query_type, :text)
    
    # MyXQLのストリーミング機能を使用
    stream_opts = [
      max_rows: max_rows,
      timeout: timeout,
      query_type: query_type
    ]
    
    try do
      # MyXQLのストリームを作成
      myxql_stream = MyXQL.stream(conn, sql, params, stream_opts)
      
      # ElixirのStreamに変換
      elixir_stream = Stream.flat_map(myxql_stream, fn 
        %MyXQL.Result{rows: rows, columns: columns} ->
          # 行をマップに変換
          Enum.map(rows, fn row ->
            columns
            |> Enum.zip(row)
            |> Enum.into(%{}, fn {col, val} -> {String.to_atom(col), val} end)
          end)
      end)
      
      {:ok, elixir_stream}
    rescue
      e in MyXQL.Error ->
        {:error, e}
    end
  end
  
  @doc """
  サーバーサイドカーソルを使用したストリーミング
  
  MySQLのサーバーサイドカーソルを明示的に使用して、
  メモリ効率を最大化します。
  """
  def create_with_cursor(conn, sql, params, opts \\ []) do
    max_rows = Keyword.get(opts, :max_rows, 500)
    cursor_name = "yesql_cursor_#{:erlang.unique_integer([:positive])}"
    
    # トランザクション内でカーソルを使用
    transaction_result = MyXQL.transaction(conn, fn tx_conn ->
      # カーソルを宣言
      cursor_sql = """
      DECLARE #{cursor_name} CURSOR FOR #{sql}
      """
      
      case MyXQL.query(tx_conn, cursor_sql, params) do
        {:ok, _} ->
          # カーソルを開く
          case MyXQL.query(tx_conn, "OPEN #{cursor_name}", []) do
            {:ok, _} ->
              stream = create_cursor_stream(tx_conn, cursor_name, max_rows)
              {:ok, stream}
            error ->
              error
          end
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
  バッファリング付きストリーミング
  
  内部バッファを使用して、ネットワークラウンドトリップを最適化します。
  """
  def create_buffered(conn, sql, params, opts \\ []) do
    buffer_size = Keyword.get(opts, :buffer_size, 10000)
    max_rows = Keyword.get(opts, :max_rows, 500)
    
    case create(conn, sql, params, max_rows: max_rows) do
      {:ok, stream} ->
        # バッファリングを追加
        buffered_stream = stream
        |> Stream.chunk_every(buffer_size)
        |> Stream.flat_map(&Function.identity/1)
        
        {:ok, buffered_stream}
        
      error ->
        error
    end
  end
  
  @doc """
  並列ストリーミング（パーティション使用）
  
  MySQLのパーティションを活用して並列にデータを取得します。
  """
  def create_parallel_partitioned(conns, _table, sql_template, params, opts \\ []) do
    partition_key = Keyword.get(opts, :partition_key, :id)
    parallelism = length(conns)
    
    # 各パーティションに対してストリームを作成
    partition_streams = conns
    |> Enum.with_index()
    |> Enum.map(fn {conn, index} ->
      # パーティション条件を追加
      partition_sql = add_partition_condition(sql_template, partition_key, index, parallelism)
      
      Task.async(fn ->
        create(conn, partition_sql, params, opts)
      end)
    end)
    
    # ストリームをマージ
    merged_stream = merge_parallel_streams(partition_streams)
    
    {:ok, merged_stream}
  end
  
  @doc """
  ストリーミングエクスポート
  
  大量のデータを効率的にファイルにエクスポートします。
  """
  def export_to_file(conn, sql, params, file_path, opts \\ []) do
    format = Keyword.get(opts, :format, :csv)
    include_headers = Keyword.get(opts, :include_headers, true)
    
    File.open!(file_path, [:write, :utf8], fn file ->
      case create(conn, sql, params, opts) do
        {:ok, stream} ->
          # 最初の行でヘッダーを書き込む
          headers_written = if include_headers do
            stream
            |> Enum.take(1)
            |> List.first()
            |> case do
              nil -> false
              first_row ->
                write_headers(file, Map.keys(first_row), format)
                write_row(file, first_row, format)
                true
            end
          else
            false
          end
          
          # 残りのデータを書き込む
          count = stream
          |> Stream.drop(if headers_written, do: 1, else: 0)
          |> Stream.map(fn row ->
            write_row(file, row, format)
            1
          end)
          |> Enum.sum()
          
          {:ok, count + if(headers_written, do: 1, else: 0)}
          
        error ->
          error
      end
    end)
  end
  
  # プライベート関数
  
  defp create_cursor_stream(conn, cursor_name, max_rows) do
    Stream.resource(
      fn -> {:continue, cursor_name} end,
      fn
        {:continue, cursor} ->
          fetch_sql = "FETCH #{max_rows} FROM #{cursor}"
          case MyXQL.query(conn, fetch_sql, []) do
            {:ok, %MyXQL.Result{rows: rows, columns: columns}} when rows != [] ->
              # 行をマップに変換
              processed_rows = Enum.map(rows, fn row ->
                columns
                |> Enum.zip(row)
                |> Enum.into(%{}, fn {col, val} -> {String.to_atom(col), val} end)
              end)
              
              {processed_rows, {:continue, cursor}}
              
            _ ->
              {:halt, {:done, cursor}}
          end
          
        {:done, cursor} ->
          {:halt, {:done, cursor}}
      end,
      fn {:done, cursor} ->
        # カーソルをクローズ
        MyXQL.query(conn, "CLOSE #{cursor}", [])
      end
    )
  end
  
  defp add_partition_condition(sql, partition_key, index, total) do
    # MOD関数を使用してパーティション分割
    condition = "MOD(#{partition_key}, #{total}) = #{index}"
    
    if String.contains?(sql, "WHERE") do
      sql <> " AND #{condition}"
    else
      sql <> " WHERE #{condition}"
    end
  end
  
  defp merge_parallel_streams(task_streams) do
    Stream.resource(
      fn -> {task_streams, [], nil} end,
      fn {tasks, buffer, current_task} ->
        # バッファからデータを返す
        if buffer != [] do
          {[hd(buffer)], {tasks, tl(buffer), current_task}}
        else
          # 新しいデータを取得
          {remaining_tasks, new_data} = fetch_from_tasks(tasks, current_task)
          
          if new_data == [] do
            {:halt, nil}
          else
            {new_data, {remaining_tasks, [], nil}}
          end
        end
      end,
      fn _ ->
        # タスクをシャットダウン
        task_streams |> Enum.each(&Task.shutdown/1)
      end
    )
  end
  
  defp fetch_from_tasks([], _), do: {[], []}
  defp fetch_from_tasks(tasks, current_task) do
    # ラウンドロビンでタスクから取得
    task = current_task || hd(tasks)
    
    case Task.yield(task, 100) do
      {:ok, {:ok, stream}} ->
        case Enum.take(stream, 10) do
          [] -> 
            # このタスクは完了
            remaining = List.delete(tasks, task)
            fetch_from_tasks(remaining, nil)
          data ->
            # next_task = get_next_task(tasks, task)  # 未使用のため一時的にコメントアウト
            {tasks, data}
        end
        
      _ ->
        # タスクがタイムアウトまたはエラー
        remaining = List.delete(tasks, task)
        fetch_from_tasks(remaining, nil)
    end
  end
  
  # 未使用の関数をコメントアウト
  # defp get_next_task(tasks, current_task) do
  #   index = Enum.find_index(tasks, &(&1 == current_task))
  #   next_index = rem(index + 1, length(tasks))
  #   Enum.at(tasks, next_index)
  # end
  
  defp write_headers(file, headers, :csv) do
    line = headers |> Enum.map(&to_string/1) |> Enum.join(",")
    IO.puts(file, line)
  end
  
  defp write_headers(file, headers, :tsv) do
    line = headers |> Enum.map(&to_string/1) |> Enum.join("\t")
    IO.puts(file, line)
  end
  
  defp write_row(file, row, :csv) do
    values = row |> Map.values() |> Enum.map(&escape_csv/1) |> Enum.join(",")
    IO.puts(file, values)
  end
  
  defp write_row(file, row, :tsv) do
    values = row |> Map.values() |> Enum.map(&to_string/1) |> Enum.join("\t")
    IO.puts(file, values)
  end
  
  defp escape_csv(nil), do: ""
  defp escape_csv(value) when is_binary(value) do
    if String.contains?(value, [",", "\"", "\n"]) do
      "\"" <> String.replace(value, "\"", "\"\"") <> "\""
    else
      value
    end
  end
  defp escape_csv(value), do: to_string(value)
  end
end