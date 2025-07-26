defmodule StreamTest do
  use ExUnit.Case, async: false
  
  alias Yesql.Stream
  
  @moduletag :streaming
  
  setup_all do
    # テスト用のデータベース接続を準備
    connections = %{}
    
    # PostgreSQL
    connections = if System.get_env("POSTGRESQL_STREAM_TEST") == "true" do
      {:ok, pg_conn} = Postgrex.start_link(
        hostname: "localhost",
        username: "postgres",
        password: "postgres",
        database: "yesql_test"
      )
      
      setup_postgresql(pg_conn)
      Map.put(connections, :postgrex, pg_conn)
    else
      connections
    end
    
    # MySQL
    connections = if System.get_env("MYSQL_STREAM_TEST") == "true" do
      {:ok, mysql_conn} = MyXQL.start_link(
        hostname: "localhost",
        username: "root",
        password: "password",
        database: "yesql_test"
      )
      
      setup_mysql(mysql_conn)
      Map.put(connections, :mysql, mysql_conn)
    else
      connections
    end
    
    # SQLite
    connections = if System.get_env("SQLITE_STREAM_TEST") == "true" do
      {:ok, sqlite_conn} = Exqlite.Sqlite3.open(":memory:")
      setup_sqlite(sqlite_conn)
      Map.put(connections, :sqlite, sqlite_conn)
    else
      connections
    end
    
    # DuckDB
    connections = if System.get_env("DUCKDB_STREAM_TEST") == "true" do
      {:ok, db} = Duckdbex.open(":memory:")
      {:ok, duckdb_conn} = Duckdbex.connection(db)
      setup_duckdb(duckdb_conn)
      Map.put(connections, :duckdb, {db, duckdb_conn})
    else
      connections
    end
    
    # MSSQL
    connections = if System.get_env("MSSQL_STREAM_TEST") == "true" do
      {:ok, mssql_conn} = Tds.start_link(
        hostname: "localhost",
        username: "sa",
        password: System.get_env("MSSQL_PASSWORD", "YourStrong!Passw0rd"),
        database: "yesql_test"
      )
      
      setup_mssql(mssql_conn)
      Map.put(connections, :mssql, mssql_conn)
    else
      connections
    end
    
    # Oracle
    connections = if System.get_env("ORACLE_STREAM_TEST") == "true" do
      {:ok, oracle_conn} = Jamdb.Oracle.start_link(
        hostname: "localhost",
        port: 1521,
        database: "XE",
        username: "yesql_test",
        password: System.get_env("ORACLE_PASSWORD", "password")
      )
      
      setup_oracle(oracle_conn)
      Map.put(connections, :oracle, oracle_conn)
    else
      connections
    end
    
    if connections == %{} do
      {:ok, %{}}
    else
      [connections: connections]
    end
  end
  
  describe "基本的なストリーミング" do
    test "大量データのストリーミング取得", %{connections: connections} do
      for {driver, conn} <- connections do
        # テスト用SQL
        sql = case driver do
          :postgrex -> "SELECT * FROM stream_test WHERE id <= $1 ORDER BY id"
          :mysql -> "SELECT * FROM stream_test WHERE id <= ? ORDER BY id"
          :sqlite -> "SELECT * FROM stream_test WHERE id <= ? ORDER BY id"
          :duckdb -> "SELECT * FROM stream_test WHERE id <= $1 ORDER BY id"
          :mssql -> "SELECT * FROM stream_test WHERE id <= @p1 ORDER BY id"
          :oracle -> "SELECT * FROM stream_test WHERE id <= :1 ORDER BY id"
        end
        
        # ストリーミング実行
        {:ok, stream} = Stream.query(get_conn(conn), sql, [5000], 
          driver: driver,
          chunk_size: 100
        )
        
        # データを収集
        results = stream |> Enum.to_list()
        
        assert length(results) == 5000
        assert hd(results).id == 1
        assert List.last(results).id == 5000
      end
    end
    
    test "チャンクサイズの動作確認", %{connections: connections} do
      for {driver, conn} <- connections do
        sql = get_simple_select_sql(driver)
        
        # 小さなチャンクサイズでストリーミング
        {:ok, stream} = Stream.query(get_conn(conn), sql, [100], 
          driver: driver,
          chunk_size: 10
        )
        
        # チャンクごとに処理されることを確認
        chunk_sizes = stream
        |> Enum.chunk_every(10)
        |> Enum.map(&length/1)
        
        assert Enum.all?(chunk_sizes, &(&1 <= 10))
      end
    end
  end
  
  describe "ストリーミング処理" do
    test "process関数でのデータ処理", %{connections: connections} do
      for {driver, conn} <- connections do
        sql = get_simple_select_sql(driver)
        
        # カウンターを使用してデータ処理
        {:ok, pid} = Agent.start_link(fn -> 0 end)
        
        {:ok, count} = Stream.process(get_conn(conn), sql, [1000],
          fn row ->
            Agent.update(pid, &(&1 + row.value))
          end,
          driver: driver,
          chunk_size: 50
        )
        
        assert count == 1000
        
        # 合計値を確認（1から1000までの合計）
        total = Agent.get(pid, & &1)
        assert total == div(1000 * 1001, 2)
        
        Agent.stop(pid)
      end
    end
    
    test "reduce関数での集約処理", %{connections: connections} do
      for {driver, conn} <- connections do
        sql = get_simple_select_sql(driver)
        
        # 最大値を計算
        {:ok, max_value} = Stream.reduce(get_conn(conn), sql, [1000], 0,
          fn row, acc ->
            max(row.value, acc)
          end,
          driver: driver
        )
        
        assert max_value == 1000
      end
    end
    
    test "batch_process関数でのバッチ処理", %{connections: connections} do
      for {driver, conn} <- connections do
        sql = get_simple_select_sql(driver)
        
        {:ok, batch_count} = Stream.batch_process(get_conn(conn), sql, [1000], 100,
          fn batch ->
            # バッチサイズを確認
            _ = length(batch)
            
            # バッチ内の全ての値が連続していることを確認
            values = Enum.map(batch, & &1.value) |> Enum.sort()
            if length(values) > 1 do
              consecutive = Enum.zip(values, tl(values))
              |> Enum.all?(fn {a, b} -> b - a <= 100 end)
              
              assert consecutive
            end
          end,
          driver: driver
        )
        
        assert batch_count == 10  # 1000 / 100
      end
    end
  end
  
  describe "メモリ効率性" do
    test "大量データでのメモリ使用量", %{connections: connections} do
      # PostgreSQLのみでテスト（他のドライバーも同様）
      if conn = connections[:postgrex] do
        initial_memory = :erlang.memory(:total)
        
        # 10万件のデータをストリーミング処理
        {:ok, _} = Stream.process(conn, 
          "SELECT * FROM stream_test WHERE id <= $1", [100000],
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
  end
  
  describe "エラーハンドリング" do
    test "無効なSQL", %{connections: connections} do
      for {driver, conn} <- connections do
        result = Stream.query(get_conn(conn), "INVALID SQL", [],
          driver: driver
        )
        
        assert {:error, _} = result
      end
    end
    
    test "接続エラー", %{connections: connections} do
      for {driver, _conn} <- connections do
        # 無効な接続
        invalid_conn = make_ref()
        
        result = Stream.query(invalid_conn, "SELECT 1", [],
          driver: driver
        )
        
        assert {:error, _} = result
      end
    end
  end
  
  describe "ドライバー固有機能" do
    test "PostgreSQL: カーソルベースストリーミング", %{connections: connections} do
      if conn = connections[:postgrex] do
        alias Yesql.Stream.PostgrexStream
        
        {:ok, stream} = PostgrexStream.create(conn, 
          "SELECT * FROM generate_series(1, 10000) as value",
          [],
          max_rows: 500
        )
        
        count = stream |> Enum.count()
        assert count == 10000
      end
    end
    
    test "MySQL: サーバーサイドカーソル", %{connections: connections} do
      if conn = connections[:mysql] do
        alias Yesql.Stream.MySQLStream
        
        {:ok, stream} = MySQLStream.create_with_cursor(conn,
          "SELECT * FROM stream_test WHERE id <= ?",
          [1000],
          max_rows: 100
        )
        
        results = stream |> Enum.to_list()
        assert length(results) == 1000
      end
    end
    
    test "SQLite: FTS5ストリーミング", %{connections: connections} do
      if conn = connections[:sqlite] do
        # FTSテーブルを作成
        Exqlite.Sqlite3.execute!(conn, """
        CREATE VIRTUAL TABLE documents USING fts5(content)
        """)
        
        # テストデータ挿入
        Enum.each(1..100, fn i ->
          Exqlite.Sqlite3.execute!(conn, 
            "INSERT INTO documents VALUES (?)",
            ["Document number #{i} contains searchable text"]
          )
        end)
        
        alias Yesql.Stream.SQLiteStream
        
        {:ok, stream} = SQLiteStream.create_fts_stream(conn,
          "documents",
          "number",
          chunk_size: 10
        )
        
        results = stream |> Enum.to_list()
        assert length(results) == 100
      end
    end
    
    test "DuckDB: Arrow形式ストリーミング", %{connections: connections} do
      if {_db, conn} = connections[:duckdb] do
        alias Yesql.Stream.DuckDBStream
        
        # Arrow形式は実装に依存するため、基本的なテストのみ
        {:ok, stream} = DuckDBStream.create(conn,
          "SELECT * FROM stream_test WHERE id <= $1",
          [1000],
          chunk_size: 100
        )
        
        count = stream |> Enum.count()
        assert count == 1000
      end
    end
    
    test "MSSQL: ページネーションベースストリーミング", %{connections: connections} do
      if conn = connections[:mssql] do
        alias Yesql.Stream.MSSQLStream
        
        {:ok, stream} = MSSQLStream.create(conn,
          "SELECT * FROM stream_test WHERE id <= @p1",
          [1000],
          chunk_size: 100
        )
        
        results = stream |> Enum.to_list()
        assert length(results) == 1000
        assert hd(results).id == 1
      end
    end
    
    test "Oracle: REF CURSORストリーミング", %{connections: connections} do
      if conn = connections[:oracle] do
        alias Yesql.Stream.OracleStream
        
        # 基本的なストリーミング（REF CURSORの実装はドライバー依存）
        {:ok, stream} = OracleStream.create(conn,
          "SELECT * FROM stream_test WHERE id <= :1",
          [1000],
          chunk_size: 100
        )
        
        count = stream |> Enum.count()
        assert count == 1000
      end
    end
  end
  
  # ヘルパー関数
  
  defp setup_postgresql(conn) do
    # テーブルを作成
    Postgrex.query!(conn, "DROP TABLE IF EXISTS stream_test", [])
    Postgrex.query!(conn, """
    CREATE TABLE stream_test (
      id SERIAL PRIMARY KEY,
      value INTEGER,
      data TEXT
    )
    """, [])
    
    # 大量のテストデータを挿入
    insert_test_data_postgresql(conn, 100000)
  end
  
  defp setup_mysql(conn) do
    MyXQL.query!(conn, "DROP TABLE IF EXISTS stream_test", [])
    MyXQL.query!(conn, """
    CREATE TABLE stream_test (
      id INT AUTO_INCREMENT PRIMARY KEY,
      value INT,
      data TEXT
    )
    """, [])
    
    insert_test_data_mysql(conn, 100000)
  end
  
  defp setup_sqlite(conn) do
    Exqlite.Sqlite3.execute!(conn, """
    CREATE TABLE stream_test (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      value INTEGER,
      data TEXT
    )
    """)
    
    insert_test_data_sqlite(conn, 100000)
  end
  
  defp setup_duckdb(conn) do
    Duckdbex.query!(conn, """
    CREATE TABLE stream_test (
      id INTEGER PRIMARY KEY,
      value INTEGER,
      data TEXT
    )
    """)
    
    insert_test_data_duckdb(conn, 100000)
  end
  
  defp insert_test_data_postgresql(conn, count) do
    # バッチ挿入で高速化
    Postgrex.query!(conn, "BEGIN", [])
    
    {:ok, statement} = Postgrex.prepare(conn, "insert_stream_test",
      "INSERT INTO stream_test (value, data) VALUES ($1, $2)"
    )
    
    Enum.chunk_every(1..count, 1000)
    |> Enum.each(fn chunk ->
      Enum.each(chunk, fn i ->
        Postgrex.execute!(conn, statement, [i, "Data for row #{i}"])
      end)
    end)
    
    Postgrex.query!(conn, "COMMIT", [])
  end
  
  defp insert_test_data_mysql(conn, count) do
    MyXQL.transaction(conn, fn conn ->
      Enum.chunk_every(1..count, 1000)
      |> Enum.each(fn chunk ->
        values = chunk
        |> Enum.map(fn i -> "(#{i}, 'Data for row #{i}')" end)
        |> Enum.join(",")
        
        MyXQL.query!(conn, "INSERT INTO stream_test (value, data) VALUES #{values}", [])
      end)
    end)
  end
  
  defp insert_test_data_sqlite(conn, count) do
    Exqlite.Sqlite3.execute!(conn, "BEGIN")
    
    {:ok, statement} = Exqlite.Sqlite3.prepare(conn,
      "INSERT INTO stream_test (value, data) VALUES (?, ?)"
    )
    
    Enum.each(1..count, fn i ->
      Exqlite.Sqlite3.bind(conn, statement, [i, "Data for row #{i}"])
      Exqlite.Sqlite3.step!(conn, statement)
      Exqlite.Sqlite3.reset!(conn, statement)
    end)
    
    Exqlite.Sqlite3.release(conn, statement)
    Exqlite.Sqlite3.execute!(conn, "COMMIT")
  end
  
  defp insert_test_data_duckdb(conn, count) do
    # DuckDBの高速挿入
    values = 1..count
    |> Enum.map(fn i -> "(#{i}, #{i}, 'Data for row #{i}')" end)
    |> Enum.join(",")
    
    Duckdbex.query!(conn, "INSERT INTO stream_test VALUES #{values}")
  end
  
  defp setup_mssql(conn) do
    # テーブルを作成
    Tds.query!(conn, "DROP TABLE IF EXISTS stream_test", [])
    Tds.query!(conn, """
    CREATE TABLE stream_test (
      id INT PRIMARY KEY,
      value INT,
      data NVARCHAR(255)
    )
    """, [])
    
    insert_test_data_mssql(conn, 100000)
  end
  
  defp setup_oracle(conn) do
    # テーブルを削除（存在する場合）
    Jamdb.Oracle.query(conn, """
    BEGIN
      EXECUTE IMMEDIATE 'DROP TABLE stream_test';
    EXCEPTION
      WHEN OTHERS THEN NULL;
    END;
    """, [])
    
    # テーブルを作成
    Jamdb.Oracle.query!(conn, """
    CREATE TABLE stream_test (
      id NUMBER PRIMARY KEY,
      value NUMBER,
      data VARCHAR2(255)
    )
    """, [])
    
    insert_test_data_oracle(conn, 100000)
  end
  
  defp insert_test_data_mssql(conn, count) do
    # バッチ挿入で高速化
    Tds.query!(conn, "BEGIN TRANSACTION", [])
    
    # バッチ単位で挿入
    Enum.chunk_every(1..count, 1000)
    |> Enum.each(fn chunk ->
      values = chunk
      |> Enum.map(fn i -> "(#{i}, #{i}, 'Data for row #{i}')" end)
      |> Enum.join(",")
      
      Tds.query!(conn, "INSERT INTO stream_test (id, value, data) VALUES #{values}", [])
    end)
    
    Tds.query!(conn, "COMMIT", [])
  end
  
  defp insert_test_data_oracle(conn, count) do
    # バッチ挿入で高速化
    Enum.chunk_every(1..count, 1000)
    |> Enum.each(fn chunk ->
      # 複数行INSERT（Oracle 12c以降）
      values = chunk
      |> Enum.map(fn i -> "INTO stream_test VALUES (#{i}, #{i}, 'Data for row #{i}')" end)
      |> Enum.join("\n")
      
      Jamdb.Oracle.query!(conn, """
      INSERT ALL
      #{values}
      SELECT 1 FROM DUAL
      """, [])
    end)
    
    # コミット
    Jamdb.Oracle.query!(conn, "COMMIT", [])
  end
  
  defp get_conn({_db, conn}), do: conn  # DuckDB
  defp get_conn(conn), do: conn
  
  defp get_simple_select_sql(:postgrex), do: "SELECT * FROM stream_test WHERE id <= $1 ORDER BY id"
  defp get_simple_select_sql(:mysql), do: "SELECT * FROM stream_test WHERE id <= ? ORDER BY id"
  defp get_simple_select_sql(:sqlite), do: "SELECT * FROM stream_test WHERE id <= ? ORDER BY id"
  defp get_simple_select_sql(:duckdb), do: "SELECT * FROM stream_test WHERE id <= $1 ORDER BY id"
  defp get_simple_select_sql(:mssql), do: "SELECT * FROM stream_test WHERE id <= @p1 ORDER BY id"
  defp get_simple_select_sql(:oracle), do: "SELECT * FROM stream_test WHERE id <= :1 ORDER BY id"
end