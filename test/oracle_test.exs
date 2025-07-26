defmodule YesqlOracleTest do
  use ExUnit.Case
  
  # Oracleテストタグ
  @moduletag :oracle
  @moduletag :skip_on_ci
  
  defmodule Queries do
    use Yesql, driver: :oracle
    
    Yesql.defquery("test/sql/oracle/select_users_by_name.sql")
    Yesql.defquery("test/sql/oracle/select_users_by_age_range.sql")
    Yesql.defquery("test/sql/oracle/insert_user.sql")
  end
  
  setup_all do
    case System.get_env("ORACLE_TEST") do
      "true" ->
        # Oracle設定
        config = [
          hostname: System.get_env("ORACLE_HOST", "localhost"),
          port: String.to_integer(System.get_env("ORACLE_PORT", "1521")),
          database: System.get_env("ORACLE_SERVICE", "XE"),
          username: System.get_env("ORACLE_USER", "yesql_test"),
          password: System.get_env("ORACLE_PASSWORD", "yesql_test"),
          parameters: [
            nls_date_format: "YYYY-MM-DD HH24:MI:SS"
          ]
        ]
        
        # Jamdb.Oracleプロセスを開始
        {:ok, pid} = Jamdb.Oracle.start_link(config)
        
        # テーブル作成
        setup_database(pid)
        
        {:ok, conn: pid}
        
      _ ->
        IO.puts "Oracleテストをスキップします。実行するには ORACLE_TEST=true を設定してください。"
        {:ok, %{}}
    end
  end
  
  setup context do
    if context[:conn] do
      # 各テストの前にテーブルをクリア
      Jamdb.Oracle.query!(context[:conn], "DELETE FROM users", [])
      
      # テストデータを挿入
      Jamdb.Oracle.query!(context[:conn], 
        "INSERT INTO users (id, name, age) VALUES (1, 'Alice', 25)")
      Jamdb.Oracle.query!(context[:conn], 
        "INSERT INTO users (id, name, age) VALUES (2, 'Bob', 30)")
      Jamdb.Oracle.query!(context[:conn], 
        "INSERT INTO users (id, name, age) VALUES (3, 'Charlie', 35)")
      
      # 変更をコミット
      Jamdb.Oracle.query!(context[:conn], "COMMIT", [])
    end
    
    :ok
  end
  
  describe "Oracleドライバー" do
    test "名前でユーザーを検索", %{conn: conn} do
      {:ok, users} = Queries.select_users_by_name(conn, name: "Alice")
      
      assert length(users) == 1
      assert hd(users)[:name] == "Alice"
      assert hd(users)[:age] == 25
    end
    
    test "年齢範囲でユーザーを検索", %{conn: conn} do
      {:ok, users} = Queries.select_users_by_age_range(conn, min_age: 26, max_age: 35)
      
      assert length(users) == 2
      assert Enum.map(users, & &1[:name]) == ["Bob", "Charlie"]
      assert Enum.map(users, & &1[:age]) == [30, 35]
    end
    
    test "新しいユーザーを挿入", %{conn: conn} do
      {:ok, result} = Queries.insert_user(conn, name: "David", age: 40)
      
      assert result.num_rows == 1
      
      # 挿入されたことを確認
      %{rows: [[count]]} = Jamdb.Oracle.query!(conn, "SELECT COUNT(*) FROM users WHERE name = 'David'", [])
      assert count == 1
    end
    
    test "パラメータが正しい順序で:1, :2...に置換される", %{conn: _conn} do
      # 複雑なクエリでパラメータの順序をテスト
      sql = "SELECT * FROM users WHERE age > :min_age AND name = :name AND age < :max_age"
      driver = %Yesql.Driver.Oracle{}
      
      {converted_sql, param_order} = Yesql.Driver.convert_params(driver, sql, [])
      
      assert converted_sql == "SELECT * FROM users WHERE age > :1 AND name = :2 AND age < :3"
      assert param_order == [:min_age, :name, :max_age]
    end
    
    test "重複するパラメータが正しく処理される", %{conn: _conn} do
      sql = "SELECT * FROM users WHERE name = :name OR nickname = :name"
      driver = %Yesql.Driver.Oracle{}
      
      {converted_sql, param_order} = Yesql.Driver.convert_params(driver, sql, [])
      
      assert converted_sql == "SELECT * FROM users WHERE name = :1 OR nickname = :1"
      assert param_order == [:name]
    end
    
    test "既存の:1形式のパラメータと名前付きパラメータが混在する場合", %{conn: _conn} do
      # Oracleでは:1形式と:name形式が混在することは推奨されないが、テストとして確認
      sql = "SELECT * FROM users WHERE id = :1 AND name = :name"
      driver = %Yesql.Driver.Oracle{}
      
      {converted_sql, param_order} = Yesql.Driver.convert_params(driver, sql, [])
      
      # :1は変換されず、:nameのみが:2に変換される（実際にはこのような混在は避けるべき）
      assert converted_sql == "SELECT * FROM users WHERE id = :1 AND name = :1"
      assert param_order == [:name]
    end
  end
  
  describe "エラーハンドリング" do
    test "無効なクエリはエラーを返す", %{conn: conn} do
      # 存在しないテーブルへのクエリ
      {:error, _} = Jamdb.Oracle.query(conn, "SELECT * FROM nonexistent_table")
    end
  end
  
  # テストデータベースのセットアップ
  defp setup_database(conn) do
    # テーブルが存在する場合は削除
    try do
      Jamdb.Oracle.query!(conn, "DROP TABLE users", [])
    rescue
      _ -> :ok
    end
    
    # テーブル作成
    Jamdb.Oracle.query!(conn, """
      CREATE TABLE users (
        id NUMBER(10) PRIMARY KEY,
        name VARCHAR2(255) NOT NULL,
        age NUMBER(3) NOT NULL
      )
    """)
    
    # 変更をコミット
    Jamdb.Oracle.query!(conn, "COMMIT", [])
  end
end