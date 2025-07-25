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
  
  defp create_stream(%Yesql.Driver.Postgrex{} = _driver, conn, sql, params, chunk_size, _opts) do
    try do
      module = Module.concat(Yesql.Stream, PostgrexStream)
      module.create(conn, sql, params, chunk_size: chunk_size)
    rescue
      _ -> {:error, :streaming_module_not_available}
    end
  end
  
  defp create_stream(%Yesql.Driver.MySQL{} = _driver, conn, sql, params, chunk_size, _opts) do
    try do
      module = Module.concat(Yesql.Stream, MySQLStream)
      module.create(conn, sql, params, chunk_size: chunk_size)
    rescue
      _ -> {:error, :streaming_module_not_available}
    end
  end
  
  defp create_stream(%Yesql.Driver.DuckDB{} = _driver, conn, sql, params, chunk_size, _opts) do
    try do
      module = Module.concat(Yesql.Stream, DuckDBStream)
      module.create(conn, sql, params, chunk_size: chunk_size)
    rescue
      _ -> {:error, :streaming_module_not_available}
    end
  end
  
  defp create_stream(%Yesql.Driver.SQLite{} = _driver, conn, sql, params, chunk_size, _opts) do
    try do
      module = Module.concat(Yesql.Stream, SQLiteStream)
      module.create(conn, sql, params, chunk_size: chunk_size)
    rescue
      _ -> {:error, :streaming_module_not_available}
    end
  end
  
  defp create_stream(%Yesql.Driver.MSSQL{} = _driver, conn, sql, params, chunk_size, opts) do
    try do
      module = Module.concat(Yesql.Stream, MSSQLStream)
      module.create(conn, sql, params, Keyword.put(opts, :chunk_size, chunk_size))
    rescue
      _ -> {:error, :streaming_module_not_available}
    end
  end
  
  defp create_stream(%Yesql.Driver.Oracle{} = _driver, conn, sql, params, chunk_size, opts) do
    try do
      module = Module.concat(Yesql.Stream, OracleStream)
      module.create(conn, sql, params, Keyword.put(opts, :chunk_size, chunk_size))
    rescue
      _ -> {:error, :streaming_module_not_available}
    end
  end
  
  defp create_stream(_, _, _, _, _, _) do
    {:error, :streaming_not_implemented}
  end
end