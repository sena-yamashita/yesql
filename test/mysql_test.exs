defmodule YesqlMySQLTest do
  use ExUnit.Case
  
  # MySQLテストタグ
  @moduletag :mysql
  @moduletag :skip_on_ci
  
  defmodule Queries do
    use Yesql, driver: :mysql
    
    Yesql.defquery("test/sql/mysql/select_users_by_name.sql")
    Yesql.defquery("test/sql/mysql/select_users_by_age_range.sql")
    Yesql.defquery("test/sql/mysql/insert_user.sql")
  end
  
  setup_all do
    case System.get_env("MYSQL_TEST") do
      "true" ->
        # MySQL設定
        config = [
          hostname: System.get_env("MYSQL_HOST", "localhost"),
          port: String.to_integer(System.get_env("MYSQL_PORT", "3306")),
          username: System.get_env("MYSQL_USER", "root"),
          password: System.get_env("MYSQL_PASSWORD", ""),
          database: System.get_env("MYSQL_DATABASE", "yesql_test")
        ]
        
        # MyXQLプロセスを開始
        {:ok, pid} = MyXQL.start_link(config)
        
        # テーブル作成
        setup_database(pid)
        
        {:ok, conn: pid}
        
      _ ->
        IO.puts "MySQLテストをスキップします。実行するには MYSQL_TEST=true を設定してください。"
        {:ok, %{}}
    end
  end
  
  setup context do
    if context[:conn] do
      # 各テストの前にテーブルをクリア
      MyXQL.query!(context[:conn], "TRUNCATE TABLE users", [])
      
      # テストデータを挿入
      MyXQL.query!(context[:conn], 
        "INSERT INTO users (id, name, age) VALUES (1, 'Alice', 25), (2, 'Bob', 30), (3, 'Charlie', 35)", [])
    end
    
    :ok
  end
  
  describe "MySQLドライバー" do
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
      {:ok, %{rows: [[count]]}} = MyXQL.query(conn, "SELECT COUNT(*) FROM users WHERE name = 'David'")
      assert count == 1
    end
    
    test "パラメータが正しい順序で置換される", %{conn: _conn} do
      # 複雑なクエリでパラメータの順序をテスト
      sql = "SELECT * FROM users WHERE age > :min_age AND name = :name AND age < :max_age"
      driver = %Yesql.Driver.MySQL{}
      
      {converted_sql, param_order} = Yesql.Driver.convert_params(driver, sql, [])
      
      assert converted_sql == "SELECT * FROM users WHERE age > ? AND name = ? AND age < ?"
      assert param_order == [:min_age, :name, :max_age]
    end
  end
  
  describe "エラーハンドリング" do
    test "無効なクエリはエラーを返す", %{conn: conn} do
      # 存在しないテーブルへのクエリ
      {:error, %MyXQL.Error{}} = MyXQL.query(conn, "SELECT * FROM nonexistent_table")
    end
  end
  
  # テストデータベースのセットアップ
  defp setup_database(conn) do
    # テーブルが存在する場合は削除
    MyXQL.query(conn, "DROP TABLE IF EXISTS users")
    
    # テーブル作成
    MyXQL.query!(conn, """
      CREATE TABLE users (
        id INT AUTO_INCREMENT PRIMARY KEY,
        name VARCHAR(255) NOT NULL,
        age INT NOT NULL
      )
    """)
  end
end