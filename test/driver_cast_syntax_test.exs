defmodule DriverCastSyntaxTest do
  use ExUnit.Case

  @moduletag :cast_syntax

  # 各ドライバー用のYesqlモジュール定義
  defmodule PostgresQuery do
    use Yesql, driver: Postgrex
    Yesql.defquery("test/sql/cast_syntax/postgres_cast.sql")
  end

  defmodule EctoQuery do
    use Yesql, driver: Ecto, conn: DriverCastSyntaxTest.TestRepo
    Yesql.defquery("test/sql/cast_syntax/postgres_cast.sql")
  end

  defmodule MySQLQuery do
    use Yesql, driver: :mysql
    Yesql.defquery("test/sql/cast_syntax/mysql_cast.sql")
  end

  defmodule SQLiteQuery do
    use Yesql, driver: :sqlite
    Yesql.defquery("test/sql/cast_syntax/sqlite_cast.sql")
  end

  defmodule DuckDBQuery do
    use Yesql, driver: :duckdb
    Yesql.defquery("test/sql/cast_syntax/duckdb_cast.sql")
  end

  defmodule MSSQLQuery do
    use Yesql, driver: :mssql
    Yesql.defquery("test/sql/cast_syntax/mssql_cast.sql")
  end

  defmodule OracleQuery do
    use Yesql, driver: :oracle
    Yesql.defquery("test/sql/cast_syntax/oracle_cast.sql")
  end

  describe "PostgreSQL :: キャスト構文" do
    setup do
      case TestHelper.new_postgrex_connection(%{module: __MODULE__}) do
        {:ok, ctx} ->
          create_cast_test_table(ctx)
          ctx

        _ ->
          {:ok, skip: true}
      end
    end

    @tag :postgres
    test ":: キャスト構文が正しく動作する", %{postgrex: conn} do
      # テストデータの挿入
      {:ok, _} =
        Postgrex.query(
          conn,
          """
            INSERT INTO cast_test (text_col, int_col, jsonb_col, array_col)
            VALUES ('123', 456, '{"key": "value"}', '{1,2,3}')
          """,
          []
        )

      # Yesqlクエリの実行（::キャスト使用）
      {:ok, results} =
        PostgresQuery.postgres_cast(conn,
          text_value: "123",
          int_value: 100,
          jsonb_value: %{"key" => "value"},
          array_value: [1, 2, 3]
        )

      assert length(results) > 0
    end

    @tag :postgres
    test "複雑な::キャスト構文", %{postgrex: conn} do
      # より複雑なキャストのテスト
      sql = """
      SELECT 
        $1::date,
        $2::time,
        $3::timestamptz,
        $4::uuid,
        $5::numeric(10,2),
        $6::interval
      """

      # UUIDをバイナリに変換
      {:ok, uuid_binary} = Ecto.UUID.dump("550e8400-e29b-41d4-a716-446655440000")
      
      {:ok, %Postgrex.Result{rows: [row]}} =
        Postgrex.query(conn, sql, [
          ~D[2024-01-01],
          ~T[12:30:45],
          ~U[2024-01-01 12:30:45Z],
          uuid_binary,
          Decimal.new("123.45"),
          %Postgrex.Interval{months: 0, days: 1, secs: 0, microsecs: 0}
        ])

      assert row != nil
    end
  end

  describe "DuckDB :: キャスト構文" do
    setup do
      case TestHelper.new_duckdb_connection(%{}) do
        {:ok, ctx} ->
          create_duckdb_cast_table(ctx)
          ctx

        _ ->
          {:ok, skip: true}
      end
    end

    @tag :duckdb
    test "DuckDBでの::キャスト", %{duckdb: conn} do
      # DuckDBもPostgreSQL互換の::をサポート
      # 注意: DuckDBはパラメータをサポートしないため、直接値を埋め込む
      sql = "SELECT '123'::INTEGER as int_val, 'test'::VARCHAR as text_val"

      {:ok, result_ref} = Duckdbex.query(conn, sql, [])
      # DuckDBは結果リファレンスを返すので、fetch_allで実際のデータを取得
      rows = Duckdbex.fetch_all(result_ref)
      assert [[123, "test"]] = rows
    end
  end

  describe "MySQL CAST関数構文" do
    setup do
      case TestHelper.new_mysql_connection(%{module: __MODULE__}) do
        {:ok, ctx} ->
          create_mysql_cast_table(ctx)
          ctx

        _ ->
          {:ok, skip: true}
      end
    end

    @tag :mysql
    test "MySQLのCAST関数", %{mysql: conn} do
      # テストデータの挿入
      MyXQL.query!(
        conn,
        """
        INSERT INTO cast_test (text_col, int_col, date_col)
        VALUES ('123', 456, '2024-01-01'), ('456', 789, '2024-01-02')
        """
      )
      
      # MySQLはCAST関数を使用
      {:ok, results} =
        MySQLQuery.mysql_cast(conn,
          text_value: "123",
          int_value: 100,
          date_value: ~D[2024-01-01]
        )

      assert length(results) > 0
    end
  end

  describe "SQLite CAST関数構文" do
    setup do
      case TestHelper.new_sqlite_connection(%{}) do
        {:ok, ctx} ->
          create_sqlite_cast_table(ctx)
          ctx

        _ ->
          {:ok, skip: true}
      end
    end

    @tag :sqlite
    test "SQLiteのCAST関数", %{sqlite: conn} do
      # SQLiteもCAST関数を使用
      {:ok, results} =
        SQLiteQuery.sqlite_cast(conn,
          text_value: "123",
          int_value: 456,
          real_value: 123.45,
          # 型親和性テスト用のパラメータ
          value: "test"
        )

      assert length(results) > 0
    end
  end

  describe "MSSQL CAST/CONVERT構文" do
    setup do
      case TestHelper.new_mssql_connection(%{module: __MODULE__}) do
        {:ok, ctx} ->
          create_mssql_cast_table(ctx)
          ctx

        _ ->
          {:ok, skip: true}
      end
    end

    @tag :mssql
    test "MSSQLのCAST/CONVERT", %{mssql: conn} do
      # MSSQLはCASTとCONVERTの両方をサポート
      {:ok, results} =
        MSSQLQuery.mssql_cast(conn,
          text_value: "123",
          int_value: 456,
          date_value: ~D[2024-01-01]
        )

      assert length(results) > 0
    end
  end

  describe "Oracle CAST関数構文" do
    setup do
      case TestHelper.new_oracle_connection(%{module: __MODULE__}) do
        {:ok, ctx} ->
          create_oracle_cast_table(ctx)
          ctx

        _ ->
          {:ok, skip: true}
      end
    end

    @tag :oracle
    test "OracleのCAST関数", %{oracle: conn} do
      # OracleはCAST関数を使用
      {:ok, results} =
        OracleQuery.oracle_cast(conn,
          text_value: "123",
          int_value: 456,
          date_value: ~D[2024-01-01]
        )

      assert length(results) > 0
    end
  end

  # ヘルパー関数

  defp create_cast_test_table(ctx) when is_list(ctx) do
    conn = ctx[:postgrex]

    {:ok, _} =
      Postgrex.query(
        conn,
        """
          CREATE TABLE IF NOT EXISTS cast_test (
            id SERIAL PRIMARY KEY,
            text_col TEXT,
            int_col INTEGER,
            jsonb_col JSONB,
            array_col INTEGER[]
          )
        """,
        []
      )

    {:ok, _} = Postgrex.query(conn, "TRUNCATE cast_test", [])
    :ok
  end

  defp create_duckdb_cast_table(ctx) when is_list(ctx) do
    conn = ctx[:duckdb]
    
    Duckdbex.query(
      conn,
      """
        CREATE TABLE IF NOT EXISTS cast_test (
          id INTEGER,
          text_col VARCHAR,
          int_col INTEGER,
          decimal_col DECIMAL(10,2)
        )
      """,
      []
    )

    Duckdbex.query(conn, "DELETE FROM cast_test", [])
    :ok
  end

  defp create_mysql_cast_table(ctx) when is_list(ctx) do
    conn = ctx[:mysql]

    MyXQL.query!(conn, """
      CREATE TABLE IF NOT EXISTS cast_test (
        id INT AUTO_INCREMENT PRIMARY KEY,
        text_col VARCHAR(255),
        int_col INT,
        date_col DATE
      )
    """)

    MyXQL.query!(conn, "TRUNCATE cast_test")
    :ok
  end

  defp create_sqlite_cast_table(ctx) when is_list(ctx) do
    conn = ctx[:sqlite]

    Exqlite.Sqlite3.execute(conn, """
      CREATE TABLE IF NOT EXISTS cast_test (
        id INTEGER PRIMARY KEY,
        text_col TEXT,
        int_col INTEGER,
        real_col REAL
      )
    """)

    Exqlite.Sqlite3.execute(conn, "DELETE FROM cast_test")
    :ok
  end

  defp create_mssql_cast_table(ctx) when is_list(ctx) do
    conn = ctx[:mssql]

    Tds.query!(
      conn,
      """
        IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='cast_test' AND xtype='U')
        CREATE TABLE cast_test (
          id INT IDENTITY(1,1) PRIMARY KEY,
          text_col NVARCHAR(255),
          int_col INT,
          date_col DATE
        )
      """,
      []
    )

    Tds.query!(conn, "TRUNCATE TABLE cast_test", [])
    :ok
  end

  defp create_oracle_cast_table(ctx) when is_list(ctx) do
    conn = ctx[:oracle]
    # Oracleテーブル作成（エラーを無視）
    try do
      {:ok, _} = Jamdb.Oracle.query(conn, "DROP TABLE cast_test", [])
    rescue
      _ -> :ok
    end

    {:ok, _} = Jamdb.Oracle.query(
      conn,
      """
        CREATE TABLE cast_test (
          id NUMBER PRIMARY KEY,
          text_col VARCHAR2(255),
          int_col NUMBER,
          date_col DATE
        )
      """,
      []
    )

    :ok
  end
end
