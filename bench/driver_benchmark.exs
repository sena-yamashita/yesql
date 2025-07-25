# ドライバーベンチマーク
# 各ドライバーのパフォーマンスを測定・比較

Mix.install([
  {:yesql, path: ".."},
  {:postgrex, "~> 0.17"},
  {:myxql, "~> 0.6", optional: true},
  {:benchee, "~> 1.0"}
])

Code.require_file("bench_helper.exs", __DIR__)

defmodule DriverBenchmark do
  @iterations 1000
  @test_user_id 1
  
  def run do
    IO.puts("YesQL ドライバーベンチマーク")
    IO.puts("=" <> String.duplicate("=", 50))
    
    # PostgreSQLベンチマーク
    if System.get_env("POSTGRESQL_BENCH") == "true" do
      run_postgresql_benchmark()
    end
    
    # MySQLベンチマーク
    if System.get_env("MYSQL_BENCH") == "true" do
      run_mysql_benchmark()
    end
    
    # 抽象化レイヤーのオーバーヘッド測定
    if System.get_env("OVERHEAD_BENCH") == "true" do
      measure_abstraction_overhead()
    end
  end
  
  defp run_postgresql_benchmark do
    IO.puts("\n### PostgreSQL ドライバーベンチマーク ###")
    
    # 接続設定
    {:ok, conn} = Postgrex.start_link(
      hostname: System.get_env("PGHOST", "localhost"),
      username: System.get_env("PGUSER", "postgres"),
      password: System.get_env("PGPASSWORD", "postgres"),
      database: System.get_env("PGDATABASE", "yesql_bench")
    )
    
    # テーブル作成とテストデータ挿入
    setup_postgresql(conn)
    
    # YesQL経由のクエリモジュール定義
    defmodule PostgresBench do
      use Yesql, driver: :postgrex
      
      # ベンチマーク用SQLファイルを動的に作成
      BenchHelper.create_test_sql_files("bench/sql/postgresql")
      
      Yesql.defquery("bench/sql/postgresql/simple_select.sql")
      Yesql.defquery("bench/sql/postgresql/multi_param_select.sql")
      Yesql.defquery("bench/sql/postgresql/complex_join.sql")
    end
    
    # ベンチマーク実行
    benchmarks = %{
      "Postgrex直接 - シンプルSELECT" => fn ->
        Postgrex.query!(conn, "SELECT * FROM users WHERE id = $1", [@test_user_id])
      end,
      
      "YesQL経由 - シンプルSELECT" => fn ->
        PostgresBench.simple_select(conn, id: @test_user_id)
      end,
      
      "Postgrex直接 - 複数パラメータ" => fn ->
        Postgrex.query!(conn, 
          "SELECT * FROM users WHERE age >= $1 AND age <= $2 AND status = $3 ORDER BY created_at DESC",
          [20, 40, "active"]
        )
      end,
      
      "YesQL経由 - 複数パラメータ" => fn ->
        PostgresBench.multi_param_select(conn, 
          min_age: 20, 
          max_age: 40, 
          status: "active"
        )
      end
    }
    
    # Bencheeを使用して詳細なベンチマーク
    Benchee.run(benchmarks, 
      time: 10,
      warmup: 2,
      memory_time: 2,
      formatters: [
        {Benchee.Formatters.Console, comparison: true}
      ]
    )
    
    # クリーンアップ
    BenchHelper.cleanup(conn, :postgresql)
    GenServer.stop(conn)
  end
  
  defp run_mysql_benchmark do
    IO.puts("\n### MySQL ドライバーベンチマーク ###")
    
    # 接続設定
    {:ok, conn} = MyXQL.start_link(
      hostname: System.get_env("MYSQL_HOST", "localhost"),
      username: System.get_env("MYSQL_USER", "root"),
      password: System.get_env("MYSQL_PASSWORD", "password"),
      database: System.get_env("MYSQL_DATABASE", "yesql_bench")
    )
    
    # テーブル作成とテストデータ挿入
    setup_mysql(conn)
    
    # YesQL経由のクエリモジュール定義
    defmodule MySQLBench do
      use Yesql, driver: :mysql
      
      BenchHelper.create_test_sql_files("bench/sql/mysql")
      
      Yesql.defquery("bench/sql/mysql/simple_select.sql")
      Yesql.defquery("bench/sql/mysql/multi_param_select.sql")
      Yesql.defquery("bench/sql/mysql/complex_join.sql")
    end
    
    # ベンチマーク実行
    benchmarks = %{
      "MyXQL直接 - シンプルSELECT" => fn ->
        MyXQL.query!(conn, "SELECT * FROM users WHERE id = ?", [@test_user_id])
      end,
      
      "YesQL経由 - シンプルSELECT" => fn ->
        MySQLBench.simple_select(conn, id: @test_user_id)
      end,
      
      "MyXQL直接 - 複数パラメータ" => fn ->
        MyXQL.query!(conn, 
          "SELECT * FROM users WHERE age >= ? AND age <= ? AND status = ? ORDER BY created_at DESC",
          [20, 40, "active"]
        )
      end,
      
      "YesQL経由 - 複数パラメータ" => fn ->
        MySQLBench.multi_param_select(conn, 
          min_age: 20, 
          max_age: 40, 
          status: "active"
        )
      end
    }
    
    Benchee.run(benchmarks,
      time: 10,
      warmup: 2,
      memory_time: 2,
      formatters: [
        {Benchee.Formatters.Console, comparison: true}
      ]
    )
    
    # クリーンアップ
    BenchHelper.cleanup(conn, :mysql)
    GenServer.stop(conn)
  end
  
  defp measure_abstraction_overhead do
    IO.puts("\n### 抽象化レイヤーオーバーヘッド測定 ###")
    IO.puts("コンパイル時のSQL解析とパラメータ変換のオーバーヘッドを測定")
    
    # パラメータ変換のオーバーヘッド測定
    sql_with_params = "SELECT * FROM users WHERE age >= :min_age AND age <= :max_age AND status = :status"
    
    # PostgreSQLドライバーのパラメータ変換
    pg_driver = %Yesql.Driver.Postgrex{}
    pg_time = BenchHelper.measure(fn ->
      Yesql.Driver.convert_params(pg_driver, sql_with_params, [])
    end, 10000)
    
    # MySQLドライバーのパラメータ変換
    mysql_driver = %Yesql.Driver.MySQL{}
    mysql_time = BenchHelper.measure(fn ->
      Yesql.Driver.convert_params(mysql_driver, sql_with_params, [])
    end, 10000)
    
    IO.puts("\nパラメータ変換オーバーヘッド:")
    BenchHelper.format_results([
      {"PostgreSQL パラメータ変換", pg_time},
      {"MySQL パラメータ変換", mysql_time}
    ])
    
    # 結果処理のオーバーヘッド測定
    sample_pg_result = %{
      columns: ["id", "name", "email", "age", "status"],
      rows: [[1, "User 1", "user1@example.com", 25, "active"]]
    }
    
    sample_mysql_result = %MyXQL.Result{
      columns: ["id", "name", "email", "age", "status"],
      rows: [[1, "User 1", "user1@example.com", 25, "active"]]
    }
    
    pg_result_time = BenchHelper.measure(fn ->
      Yesql.Driver.process_result(pg_driver, {:ok, sample_pg_result})
    end, 10000)
    
    mysql_result_time = BenchHelper.measure(fn ->
      Yesql.Driver.process_result(mysql_driver, {:ok, sample_mysql_result})
    end, 10000)
    
    IO.puts("\n結果処理オーバーヘッド:")
    BenchHelper.format_results([
      {"PostgreSQL 結果処理", pg_result_time},
      {"MySQL 結果処理", mysql_result_time}
    ])
  end
  
  defp setup_postgresql(conn) do
    # テーブル作成
    Postgrex.query!(conn, BenchHelper.create_tables_sql(:postgresql), [])
    
    # テストデータ挿入
    BenchHelper.insert_test_data(conn, :postgresql, 1000)
    
    # インデックス作成
    Postgrex.query!(conn, "CREATE INDEX IF NOT EXISTS idx_users_status ON users(status)", [])
    Postgrex.query!(conn, "CREATE INDEX IF NOT EXISTS idx_users_age ON users(age)", [])
    Postgrex.query!(conn, "CREATE INDEX IF NOT EXISTS idx_posts_user_id ON posts(user_id)", [])
  end
  
  defp setup_mysql(conn) do
    # テーブル作成
    MyXQL.query!(conn, BenchHelper.create_tables_sql(:mysql), [])
    
    # テストデータ挿入
    BenchHelper.insert_test_data(conn, :mysql, 1000)
    
    # インデックス作成
    MyXQL.query!(conn, "CREATE INDEX idx_users_status ON users(status)", [])
    MyXQL.query!(conn, "CREATE INDEX idx_users_age ON users(age)", [])
    MyXQL.query!(conn, "CREATE INDEX idx_posts_user_id ON posts(user_id)", [])
  end
end

# ベンチマーク実行
DriverBenchmark.run()