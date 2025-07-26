defmodule SQLiteTest do
  use ExUnit.Case, async: false
  
  @moduletag :sqlite
  
  # 環境変数でSQLiteテストを有効化
  
  setup_all do
    # CI環境またはSQLITE_TEST=trueで実行
    if System.get_env("CI") || System.get_env("SQLITE_TEST") == "true" do
        # メモリデータベースでテスト
        {:ok, conn} = Exqlite.Sqlite3.open(":memory:")
        
        # テーブル作成
        create_tables_sql = """
        CREATE TABLE users (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          age INTEGER,
          email TEXT UNIQUE,
          inserted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );
        
        CREATE TABLE posts (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          user_id INTEGER REFERENCES users(id),
          title TEXT,
          body TEXT,
          inserted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );
        """
        
        {:ok, _} = Exqlite.Sqlite3.execute(conn, create_tables_sql)
        
        # テストデータ挿入
        {:ok, statement} = Exqlite.Sqlite3.prepare(conn, "INSERT INTO users (name, age, email) VALUES (?, ?, ?)")
        :ok = Exqlite.Sqlite3.bind(statement, ["Alice", 25, "alice@example.com"])
        :done = Exqlite.Sqlite3.step(conn, statement)
        :ok = Exqlite.Sqlite3.release(conn, statement)
        
        {:ok, statement} = Exqlite.Sqlite3.prepare(conn, "INSERT INTO users (name, age, email) VALUES (?, ?, ?)")
        :ok = Exqlite.Sqlite3.bind(statement, ["Bob", 30, "bob@example.com"])
        :done = Exqlite.Sqlite3.step(conn, statement)
        :ok = Exqlite.Sqlite3.release(conn, statement)
        
        # SQLファイル作成
        File.mkdir_p!("test/sql/sqlite")
        
        File.write!("test/sql/sqlite/select_users.sql", """
        -- name: select_users
        -- SQLiteで全ユーザーを取得
        SELECT * FROM users ORDER BY id;
        """)
        
        File.write!("test/sql/sqlite/select_user_by_id.sql", """
        -- name: select_user_by_id
        -- SQLiteで特定のユーザーを取得
        SELECT * FROM users WHERE id = :id;
        """)
        
        File.write!("test/sql/sqlite/select_users_by_age.sql", """
        -- name: select_users_by_age
        -- SQLiteで年齢範囲でユーザーを検索
        SELECT * FROM users WHERE age >= :min_age AND age <= :max_age ORDER BY age;
        """)
        
        File.write!("test/sql/sqlite/insert_user.sql", """
        -- name: insert_user
        -- SQLiteにユーザーを挿入
        INSERT INTO users (name, age, email) VALUES (:name, :age, :email);
        """)
        
        File.write!("test/sql/sqlite/update_user_age.sql", """
        -- name: update_user_age
        -- SQLiteでユーザーの年齢を更新
        UPDATE users SET age = :age WHERE id = :id;
        """)
        
        File.write!("test/sql/sqlite/delete_user.sql", """
        -- name: delete_user
        -- SQLiteからユーザーを削除
        DELETE FROM users WHERE id = :id;
        """)
        
        File.write!("test/sql/sqlite/complex_join.sql", """
        -- name: complex_join
        -- SQLiteで複雑なJOINクエリ
        SELECT u.name, u.age, COUNT(p.id) as post_count
        FROM users u
        LEFT JOIN posts p ON u.id = p.user_id
        WHERE u.age >= :min_age
        GROUP BY u.id, u.name, u.age
        ORDER BY post_count DESC;
        """)
        
        {:ok, conn: conn}
    else
      IO.puts "SQLiteテストをスキップします。実行するには SQLITE_TEST=true を設定してください。"
          {:ok, skip: true}
    end
  end
  
  setup %{conn: _conn} = context do
    # 各テスト用のコンテキスト設定
    context
  end
  
  defmodule Queries do
    use Yesql, driver: :sqlite
    
    Yesql.defquery("test/sql/sqlite/select_users.sql")
    Yesql.defquery("test/sql/sqlite/select_user_by_id.sql")
    Yesql.defquery("test/sql/sqlite/select_users_by_age.sql")
    Yesql.defquery("test/sql/sqlite/insert_user.sql")
    Yesql.defquery("test/sql/sqlite/update_user_age.sql")
    Yesql.defquery("test/sql/sqlite/delete_user.sql")
    Yesql.defquery("test/sql/sqlite/complex_join.sql")
  end
  
  describe "基本的なクエリ" do
    test "全ユーザーの取得", %{conn: conn} do
      # Aliceを検索
      {:ok, alice_results} = Queries.select_users(conn, name: "Alice")
      assert length(alice_results) == 1
      assert hd(alice_results).name == "Alice"
      
      # Bobを検索
      {:ok, bob_results} = Queries.select_users(conn, name: "Bob")
      assert length(bob_results) == 1
      assert hd(bob_results).name == "Bob"
    end
    
    test "IDによるユーザー取得", %{conn: conn} do
      {:ok, users} = Queries.select_user_by_id(conn, id: 1)
      
      assert length(users) == 1
      assert hd(users).name == "Alice"
    end
    
    test "年齢範囲によるユーザー検索", %{conn: conn} do
      {:ok, users} = Queries.select_users_by_age(conn, min_age: 20, max_age: 26)
      
      assert length(users) == 1
      assert hd(users).name == "Alice"
    end
  end
  
  describe "データ変更操作" do
    test "ユーザーの挿入", %{conn: conn} do
      {:ok, _} = Queries.insert_user(conn, 
        name: "Charlie", 
        age: 35, 
        email: "charlie@example.com"
      )
      
      # 挿入後のCharlieを検索
      {:ok, results} = Queries.select_users(conn, name: "Charlie")
      assert length(results) == 1
    end
    
    test "ユーザーの更新", %{conn: conn} do
      {:ok, _} = Queries.update_user_age(conn, id: 1, age: 26)
      
      {:ok, users} = Queries.select_user_by_id(conn, id: 1)
      assert hd(users).age == 26
    end
    
    test "ユーザーの削除", %{conn: conn} do
      {:ok, _} = Queries.delete_user(conn, id: 2)
      
      # Bobが削除されたことを確認
      {:ok, bob_results} = Queries.select_users(conn, name: "Bob")
      assert length(bob_results) == 0
      
      # Aliceが残っていることを確認
      {:ok, alice_results} = Queries.select_users(conn, name: "Alice")
      assert length(alice_results) == 1
    end
  end
  
  describe "SQLite固有の機能" do
    test "AUTOINCREMENT主キー", %{conn: conn} do
      # 複数のユーザーを追加
      {:ok, _} = Queries.insert_user(conn, name: "User1", age: 20, email: "user1@example.com")
      {:ok, _} = Queries.insert_user(conn, name: "User2", age: 21, email: "user2@example.com")
      
      # 挿入したユーザーを検索
      {:ok, results} = Queries.select_users(conn, name: "Eve")
      assert length(results) == 1
      assert hd(results).id != nil
    end
    
    test "複雑なJOINクエリ", %{conn: conn} do
      # ポストデータを追加
      insert_post_sql = "INSERT INTO posts (user_id, title, body) VALUES (?, ?, ?)"
      {:ok, statement} = Exqlite.Sqlite3.prepare(conn, insert_post_sql)
      
      # Aliceに2つのポスト
      :ok = Exqlite.Sqlite3.bind(statement, [1, "Post 1", "Body 1"])
      :done = Exqlite.Sqlite3.step(conn, statement)
      :ok = Exqlite.Sqlite3.release(conn, statement)
      
      {:ok, statement} = Exqlite.Sqlite3.prepare(conn, insert_post_sql)
      :ok = Exqlite.Sqlite3.bind(statement, [1, "Post 2", "Body 2"])
      :done = Exqlite.Sqlite3.step(conn, statement)
      :ok = Exqlite.Sqlite3.release(conn, statement)
      
      # 結果を確認
      {:ok, results} = Queries.complex_join(conn, min_age: 20)
      
      assert length(results) == 2
      alice_result = Enum.find(results, &(&1.name == "Alice"))
      assert alice_result.post_count == 2
      
      bob_result = Enum.find(results, &(&1.name == "Bob"))
      assert bob_result.post_count == 0
    end
  end
  
  describe "メモリデータベース" do
    test "メモリDBの高速性", %{conn: conn} do
      # 大量のデータ挿入のパフォーマンステスト
      start_time = System.monotonic_time(:millisecond)
      
      Enum.each(1..100, fn i ->
        {:ok, _} = Queries.insert_user(conn,
          name: "User#{i}",
          age: 20 + rem(i, 50),
          email: "user#{i}@example.com"
        )
      end)
      
      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time
      
      # メモリDBなので非常に高速なはず
      assert duration < 100  # 100ms以内
      
      # テストユーザーを検索
      {:ok, results} = Queries.select_users(conn, name: "Performance Test User")
      assert length(results) == 100
    end
  end
end