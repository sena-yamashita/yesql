# Test COPY TO with parameters in DuckDB

defmodule TestCopyTo do
  def test do
    {:ok, db} = Duckdbex.open(":memory:")
    {:ok, conn} = Duckdbex.connection(db)
    
    # Create test table
    Duckdbex.query(conn, """
    CREATE TABLE test_data (
      id INTEGER,
      name VARCHAR,
      value DOUBLE
    )
    """, [])
    
    # Insert test data
    Duckdbex.query(conn, """
    INSERT INTO test_data VALUES 
      (1, 'Alice', 100.5),
      (2, 'Bob', 200.75),
      (3, 'Charlie', 300.0)
    """, [])
    
    # Test 1: COPY TO with parameter (will likely fail)
    IO.puts("\n=== Test 1: COPY TO with parameter ===")
    csv_path = "/tmp/test_export.csv"
    sql = "COPY test_data TO $1 (HEADER, DELIMITER ',')"
    
    case Duckdbex.query(conn, sql, [csv_path]) do
      {:ok, _} -> 
        IO.puts("Success with parameter!")
        if File.exists?(csv_path) do
          IO.puts("File created: #{csv_path}")
          content = File.read!(csv_path)
          IO.puts("Content: #{String.slice(content, 0, 100)}...")
          File.rm!(csv_path)
        end
      {:error, error} -> 
        IO.puts("Error with parameter: #{error}")
    end
    
    # Test 2: COPY TO with string replacement
    IO.puts("\n=== Test 2: COPY TO with string replacement ===")
    sql_replaced = String.replace(sql, "$1", "'#{csv_path}'")
    IO.puts("SQL: #{sql_replaced}")
    
    case Duckdbex.query(conn, sql_replaced, []) do
      {:ok, _} -> 
        IO.puts("Success with string replacement!")
        if File.exists?(csv_path) do
          IO.puts("File created: #{csv_path}")
          content = File.read!(csv_path)
          IO.puts("Content:\n#{content}")
          File.rm!(csv_path)
        end
      {:error, error} -> 
        IO.puts("Error with string replacement: #{error}")
    end
    
    # Test 3: Using YesQL driver
    IO.puts("\n=== Test 3: Using YesQL DuckDB driver ===")
    driver = %Yesql.Driver.DuckDB{}
    
    result = Yesql.Driver.execute(driver, conn, sql, [csv_path])
    case result do
      {:ok, _} -> 
        IO.puts("Success with YesQL driver!")
        if File.exists?(csv_path) do
          IO.puts("File created: #{csv_path}")
          File.rm!(csv_path)
        end
      {:error, error} -> 
        IO.puts("Error with YesQL driver: #{error}")
    end
  end
end

TestCopyTo.test()