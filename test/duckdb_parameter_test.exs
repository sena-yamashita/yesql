defmodule DuckDBParameterTest do
  use ExUnit.Case
  
  defmodule TestQueries do
    use Yesql, driver: :duckdb
    
    def simple_param_sql do
      "SELECT $1 AS value"
    end
    
    def file_path_sql do
      "CREATE OR REPLACE TABLE test_import AS SELECT * FROM read_csv_auto($1)"
    end
    
    def multiple_params_sql do
      "SELECT $1 AS first, $2 AS second, $3 AS third"
    end
  end
  
  setup_all do
    {:ok, db} = Duckdbex.open(":memory:")
    {:ok, conn} = Duckdbex.connection(db)
    
    # テスト用のCSVファイルを作成
    test_csv_path = Path.join(System.tmp_dir!(), "test_duckdb.csv")
    File.write!(test_csv_path, """
    id,name,value
    1,Alice,100
    2,Bob,200
    3,Charlie,300
    """)
    
    on_exit(fn ->
      File.rm(test_csv_path)
    end)
    
    {:ok, conn: conn, csv_path: test_csv_path}
  end
  
  test "simple parameter query", %{conn: conn} do
    sql = TestQueries.simple_param_sql()
    
    # 直接DuckDBexを使用してテスト（プリペアドステートメント）
    IO.puts("\n=== Direct DuckDBex with prepared statement ===")
    case Duckdbex.prepare_statement(conn, sql) do
      {:ok, stmt} ->
        case Duckdbex.execute_statement(stmt, ["test_value"]) do
          {:ok, result} ->
            case Duckdbex.fetch_all(result) do
              {:ok, rows} -> IO.inspect(rows, label: "Success with prepared statement")
              error -> IO.inspect(error, label: "Fetch error")
            end
          error ->
            IO.inspect(error, label: "Execute error")
        end
      error ->
        IO.inspect(error, label: "Prepare error")
    end
    
    # Yesqlドライバーを通してテスト
    IO.puts("\n=== Using Yesql Driver ===")
    driver = %Yesql.Driver.DuckDB{}
    case Yesql.Driver.execute(driver, conn, sql, ["test_value"]) do
      {:ok, result} ->
        IO.inspect(result, label: "Yesql driver success")
      error ->
        IO.inspect(error, label: "Yesql driver error")
    end
  end
  
  test "file path parameter", %{conn: conn, csv_path: csv_path} do
    sql = TestQueries.file_path_sql()
    
    # 直接SQLを実行（パラメータなし）
    direct_sql = String.replace(sql, "$1", "'#{csv_path}'")
    IO.puts("\n=== Direct SQL (no parameters) ===")
    IO.puts("SQL: #{direct_sql}")
    
    case Duckdbex.query(conn, direct_sql, []) do
      {:ok, _} -> IO.puts("✓ Direct execution successful")
      error -> IO.inspect(error, label: "Direct execution error")
    end
    
    # プリペアドステートメントを使用
    IO.puts("\n=== Using prepared statement ===")
    case Duckdbex.prepare_statement(conn, sql) do
      {:ok, stmt} ->
        case Duckdbex.execute_statement(stmt, [csv_path]) do
          {:ok, _} -> IO.puts("✓ Prepared statement execution successful")
          error -> IO.inspect(error, label: "Execute error")
        end
      error ->
        IO.inspect(error, label: "Prepare error")
    end
    
    # Yesqlドライバーを使用
    IO.puts("\n=== Using Yesql Driver ===")
    driver = %Yesql.Driver.DuckDB{}
    case Yesql.Driver.execute(driver, conn, sql, [csv_path]) do
      {:ok, _} -> IO.puts("✓ Yesql driver execution successful")
      error -> IO.inspect(error, label: "Yesql driver error")
    end
  end
  
  test "DuckDB parameter format investigation", %{conn: conn} do
    # DuckDBがサポートするパラメータ形式を調査
    
    # まずシンプルなクエリをテスト
    IO.puts("\n=== Testing simple query without parameters ===")
    case Duckdbex.query(conn, "SELECT 42 as answer", []) do
      {:ok, result} ->
        case Duckdbex.fetch_all(result) do
          {:ok, rows} -> IO.inspect(rows, label: "Simple query result")
          error -> IO.inspect(error, label: "Fetch error")
        end
      error ->
        IO.inspect(error, label: "Query error")
    end
    
    # query/3を直接使用してテスト
    IO.puts("\n=== Testing query/3 directly ===")
    
    # $1形式
    IO.puts("\nTesting $1 format with query/3:")
    case Duckdbex.query(conn, "SELECT $1", ["test"]) do
      {:ok, result} ->
        case Duckdbex.fetch_all(result) do
          {:ok, rows} -> IO.inspect(rows, label: "✓ Success")
          error -> IO.inspect(error, label: "Fetch error")
        end
      error ->
        IO.inspect(error, label: "✗ Query error")
    end
    
    # ?形式
    IO.puts("\nTesting ? format with query/3:")
    case Duckdbex.query(conn, "SELECT ?", ["test"]) do
      {:ok, result} ->
        case Duckdbex.fetch_all(result) do
          {:ok, rows} -> IO.inspect(rows, label: "✓ Success")
          error -> IO.inspect(error, label: "Fetch error")
        end
      error ->
        IO.inspect(error, label: "✗ Query error")
    end
    
    # プリペアドステートメントをテスト
    IO.puts("\n=== Testing prepared statements ===")
    
    # $1形式をプリペアドステートメントでテスト
    test_prepared_query("$1 format", conn, "SELECT $1", ["test"])
    
    # ?形式をプリペアドステートメントでテスト
    test_prepared_query("? format", conn, "SELECT ?", ["test"])
  end
  
  defp test_prepared_query(label, conn, sql, params) do
    IO.puts("\nTesting #{label} with prepared statement:")
    IO.puts("SQL: #{sql}")
    IO.puts("Params: #{inspect(params)}")
    
    case Duckdbex.prepare_statement(conn, sql) do
      {:ok, stmt} ->
        case Duckdbex.execute_statement(stmt, params) do
          {:ok, result} ->
            case Duckdbex.fetch_all(result) do
              {:ok, rows} ->
                IO.puts("✓ Success")
                IO.puts("  Result: #{inspect(rows)}")
              error -> 
                IO.puts("✗ Fetch error: #{inspect(error)}")
            end
          error ->
            IO.puts("✗ Execute error: #{inspect(error)}")
        end
      error ->
        IO.puts("✗ Prepare error: #{inspect(error)}")
    end
  end
end