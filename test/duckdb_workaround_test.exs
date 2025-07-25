defmodule DuckDBWorkaroundTest do
  use ExUnit.Case
  
  defmodule TestQueries do
    use Yesql, driver: :duckdb
    
    Yesql.defquery("test/sql/duckdb_select_param.sql")
    Yesql.defquery("test/sql/duckdb_import_csv.sql")
  end
  
  setup_all do
    {:ok, db} = Duckdbex.open(":memory:")
    {:ok, conn} = Duckdbex.connection(db)
    
    # テスト用のテーブルを作成
    Duckdbex.query(conn, """
    CREATE TABLE test_table (
      id INTEGER,
      name VARCHAR,
      value DOUBLE,
      created_at DATE
    )
    """, [])
    
    # テストデータを挿入
    Duckdbex.query(conn, """
    INSERT INTO test_table VALUES 
      (1, 'Alice', 100.5, '2024-01-01'),
      (2, 'Bob', 200.75, '2024-01-02'),
      (3, 'Charlie', 300.0, '2024-01-03')
    """, [])
    
    # テスト用CSVファイルを作成
    csv_path = Path.join(System.tmp_dir!(), "test_yesql_duckdb.csv")
    File.write!(csv_path, """
    id,name,value
    4,David,400
    5,Eve,500
    """)
    
    on_exit(fn ->
      File.rm(csv_path)
    end)
    
    {:ok, conn: conn, csv_path: csv_path}
  end
  
  test "simple parameter replacement", %{conn: conn} do
    # SELECT * FROM test_table WHERE id = $1
    result = TestQueries.duckdb_select_param(conn, id: 1)
    
    assert {:ok, rows} = result
    assert length(rows) == 1
    # DuckDBは数値をそのまま返し、日付をタプルで返す
    assert %{id: 1, name: "Alice", value: 100.5, created_at: {2024, 1, 1}} = hd(rows)
  end
  
  test "multiple parameters", %{conn: conn} do
    # 複数パラメータのテスト
    sql = "SELECT * FROM test_table WHERE id > $1 AND value < $2"
    
    # DuckDBドライバーを直接テスト
    driver = %Yesql.Driver.DuckDB{}
    result = Yesql.Driver.execute(driver, conn, sql, [1, 250.0])
    
    assert {:ok, %{rows: rows}} = result
    assert length(rows) == 1
  end
  
  test "string parameter with quotes", %{conn: conn} do
    # 文字列パラメータのエスケープテスト
    sql = "SELECT * FROM test_table WHERE name = $1"
    
    driver = %Yesql.Driver.DuckDB{}
    result = Yesql.Driver.execute(driver, conn, sql, ["Alice"])
    
    assert {:ok, %{rows: [row]}} = result
    assert row == [1, "Alice", 100.5, {2024, 1, 1}]
  end
  
  test "CSV import with file path", %{conn: conn, csv_path: csv_path} do
    # CREATE OR REPLACE TABLE imported_data AS SELECT * FROM read_csv_auto($1)
    result = TestQueries.duckdb_import_csv(conn, file_path: csv_path)
    
    assert {:ok, _} = result
    
    # インポートされたデータを確認
    {:ok, check_result} = Duckdbex.query(conn, "SELECT COUNT(*) as count FROM imported_data", [])
    rows = Duckdbex.fetch_all(check_result)
    assert [[count]] = rows
    assert count == 2
  end
end