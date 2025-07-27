defmodule Yesql.Unit.DriverParameterTest do
  use ExUnit.Case, async: true

  @moduletag :unit

  describe "PostgreSQL ドライバー（$1, $2形式）" do
    setup do
      {:ok, driver} = Yesql.DriverFactory.create(:postgrex)
      {:ok, driver: driver}
    end

    test "基本的なパラメータ変換", %{driver: driver} do
      sql = "SELECT * FROM users WHERE id = :id"
      {converted, params} = Yesql.Driver.convert_params(driver, sql, [])

      assert converted == "SELECT * FROM users WHERE id = $1"
      assert params == [:id]
    end

    test "複数パラメータの変換", %{driver: driver} do
      sql = "SELECT * FROM users WHERE name = :name AND age > :age"
      {converted, params} = Yesql.Driver.convert_params(driver, sql, [])

      assert converted == "SELECT * FROM users WHERE name = $1 AND age > $2"
      assert params == [:name, :age]
    end

    test "同じパラメータの再利用", %{driver: driver} do
      sql = "SELECT * FROM users WHERE created_at > :date OR updated_at > :date"
      {converted, params} = Yesql.Driver.convert_params(driver, sql, [])

      assert converted == "SELECT * FROM users WHERE created_at > $1 OR updated_at > $1"
      assert params == [:date]
    end

    test "PostgreSQL特有のキャスト構文", %{driver: driver} do
      sql = "SELECT :id::bigint, :data::jsonb, :tags::text[]"
      {converted, params} = Yesql.Driver.convert_params(driver, sql, [])

      assert converted == "SELECT $1::bigint, $2::jsonb, $3::text[]"
      assert params == [:id, :data, :tags]
    end

    test "INSERT文でのパラメータ", %{driver: driver} do
      sql = "INSERT INTO users (name, email, age) VALUES (:name, :email, :age)"
      {converted, params} = Yesql.Driver.convert_params(driver, sql, [])

      assert converted == "INSERT INTO users (name, email, age) VALUES ($1, $2, $3)"
      assert params == [:name, :email, :age]
    end

    test "複雑なクエリでの順序保持", %{driver: driver} do
      sql = """
      WITH new_user AS (
        INSERT INTO users (name, age) VALUES (:name, :age)
        RETURNING id
      )
      INSERT INTO profiles (user_id, bio) 
      SELECT id, :bio FROM new_user
      """

      {converted, params} = Yesql.Driver.convert_params(driver, sql, [])

      assert converted =~ "VALUES ($1, $2)"
      assert converted =~ "SELECT id, $3"
      assert params == [:name, :age, :bio]
    end
  end

  describe "MySQL ドライバー（?形式）" do
    setup do
      {:ok, driver} = Yesql.DriverFactory.create(:mysql)
      {:ok, driver: driver}
    end

    test "基本的なパラメータ変換", %{driver: driver} do
      sql = "SELECT * FROM users WHERE id = :id"
      {converted, params} = Yesql.Driver.convert_params(driver, sql, [])

      assert converted == "SELECT * FROM users WHERE id = ?"
      assert params == [:id]
    end

    test "複数パラメータの変換", %{driver: driver} do
      sql = "SELECT * FROM users WHERE name = :name AND age > :age"
      {converted, params} = Yesql.Driver.convert_params(driver, sql, [])

      assert converted == "SELECT * FROM users WHERE name = ? AND age > ?"
      assert params == [:name, :age]
    end

    test "同じパラメータの再利用（位置が重要）", %{driver: driver} do
      sql = "SELECT * FROM users WHERE created_at > :date OR updated_at > :date"
      {converted, params} = Yesql.Driver.convert_params(driver, sql, [])

      assert converted == "SELECT * FROM users WHERE created_at > ? OR updated_at > ?"
      # MySQLでは同じパラメータも複数回必要
      assert params == [:date, :date]
    end

    test "CAST関数形式", %{driver: driver} do
      sql = "SELECT CAST(:value AS CHAR), CAST(:number AS UNSIGNED)"
      {converted, params} = Yesql.Driver.convert_params(driver, sql, [])

      assert converted == "SELECT CAST(? AS CHAR), CAST(? AS UNSIGNED)"
      assert params == [:value, :number]
    end

    test "プリペアドステートメントでの使用", %{driver: driver} do
      sql = "INSERT INTO logs (level, message, created_at) VALUES (:level, :message, NOW())"
      {converted, params} = Yesql.Driver.convert_params(driver, sql, [])

      assert converted == "INSERT INTO logs (level, message, created_at) VALUES (?, ?, NOW())"
      assert params == [:level, :message]
    end
  end

  describe "MSSQL ドライバー（@p1, @p2形式）" do
    setup do
      {:ok, driver} = Yesql.DriverFactory.create(:mssql)
      {:ok, driver: driver}
    end

    test "基本的なパラメータ変換", %{driver: driver} do
      sql = "SELECT * FROM users WHERE id = :id"
      {converted, params} = Yesql.Driver.convert_params(driver, sql, [])

      assert converted == "SELECT * FROM users WHERE id = @p1"
      assert params == [:id]
    end

    test "複数パラメータの変換", %{driver: driver} do
      sql = "SELECT * FROM users WHERE name = :name AND age > :age"
      {converted, params} = Yesql.Driver.convert_params(driver, sql, [])

      assert converted == "SELECT * FROM users WHERE name = @p1 AND age > @p2"
      assert params == [:name, :age]
    end

    test "同じパラメータの再利用", %{driver: driver} do
      sql = "SELECT * FROM users WHERE created_at > :date OR updated_at > :date"
      {converted, params} = Yesql.Driver.convert_params(driver, sql, [])

      assert converted == "SELECT * FROM users WHERE created_at > @p1 OR updated_at > @p1"
      assert params == [:date]
    end

    test "CAST関数とCONVERT関数", %{driver: driver} do
      sql = "SELECT CAST(:value AS VARCHAR(100)), CONVERT(INT, :number)"
      {converted, params} = Yesql.Driver.convert_params(driver, sql, [])

      assert converted == "SELECT CAST(@p1 AS VARCHAR(100)), CONVERT(INT, @p2)"
      assert params == [:value, :number]
    end

    test "ストアドプロシージャのパラメータ", %{driver: driver} do
      sql = "EXEC sp_GetUsersByAgeRange @MinAge = :min_age, @MaxAge = :max_age"
      {converted, params} = Yesql.Driver.convert_params(driver, sql, [])

      assert converted == "EXEC sp_GetUsersByAgeRange @MinAge = @p1, @MaxAge = @p2"
      assert params == [:min_age, :max_age]
    end
  end

  describe "Oracle ドライバー（:1, :2形式）" do
    setup do
      {:ok, driver} = Yesql.DriverFactory.create(:oracle)
      {:ok, driver: driver}
    end

    test "基本的なパラメータ変換", %{driver: driver} do
      sql = "SELECT * FROM users WHERE id = :id"
      {converted, params} = Yesql.Driver.convert_params(driver, sql, [])

      assert converted == "SELECT * FROM users WHERE id = :1"
      assert params == [:id]
    end

    test "複数パラメータの変換", %{driver: driver} do
      sql = "SELECT * FROM users WHERE name = :name AND age > :age"
      {converted, params} = Yesql.Driver.convert_params(driver, sql, [])

      assert converted == "SELECT * FROM users WHERE name = :1 AND age > :2"
      assert params == [:name, :age]
    end

    test "同じパラメータの再利用", %{driver: driver} do
      sql = "SELECT * FROM users WHERE created_at > :date OR updated_at > :date"
      {converted, params} = Yesql.Driver.convert_params(driver, sql, [])

      assert converted == "SELECT * FROM users WHERE created_at > :1 OR updated_at > :1"
      assert params == [:date]
    end

    test "Oracle特有のTO_DATE関数", %{driver: driver} do
      sql = "SELECT * FROM orders WHERE order_date >= TO_DATE(:start_date, 'YYYY-MM-DD')"
      {converted, params} = Yesql.Driver.convert_params(driver, sql, [])

      assert converted == "SELECT * FROM orders WHERE order_date >= TO_DATE(:1, 'YYYY-MM-DD')"
      assert params == [:start_date]
    end

    test "PL/SQLブロック内のパラメータ", %{driver: driver} do
      sql = """
      BEGIN
        UPDATE users SET last_login = SYSDATE WHERE id = :user_id;
        INSERT INTO login_history (user_id, login_time) VALUES (:user_id, SYSDATE);
      END;
      """

      {converted, params} = Yesql.Driver.convert_params(driver, sql, [])

      assert converted =~ "WHERE id = :1"
      assert converted =~ "VALUES (:1, SYSDATE)"
      assert params == [:user_id]
    end
  end

  describe "SQLite ドライバー（?形式）" do
    setup do
      {:ok, driver} = Yesql.DriverFactory.create(:sqlite)
      {:ok, driver: driver}
    end

    test "基本的なパラメータ変換", %{driver: driver} do
      sql = "SELECT * FROM users WHERE id = :id"
      {converted, params} = Yesql.Driver.convert_params(driver, sql, [])

      assert converted == "SELECT * FROM users WHERE id = ?"
      assert params == [:id]
    end

    test "複数パラメータの変換", %{driver: driver} do
      sql = "INSERT INTO users (name, email) VALUES (:name, :email)"
      {converted, params} = Yesql.Driver.convert_params(driver, sql, [])

      assert converted == "INSERT INTO users (name, email) VALUES (?, ?)"
      assert params == [:name, :email]
    end

    test "SQLite特有のdate関数", %{driver: driver} do
      sql = "SELECT * FROM events WHERE date(created_at) = date(:target_date)"
      {converted, params} = Yesql.Driver.convert_params(driver, sql, [])

      assert converted == "SELECT * FROM events WHERE date(created_at) = date(?)"
      assert params == [:target_date]
    end
  end

  describe "DuckDB ドライバー（$1, $2形式）" do
    setup do
      {:ok, driver} = Yesql.DriverFactory.create(:duckdb)
      {:ok, driver: driver}
    end

    test "基本的なパラメータ変換", %{driver: driver} do
      sql = "SELECT * FROM users WHERE id = :id"
      {converted, params} = Yesql.Driver.convert_params(driver, sql, [])

      assert converted == "SELECT * FROM users WHERE id = $1"
      assert params == [:id]
    end

    test "DuckDB特有のキャスト構文", %{driver: driver} do
      sql = "SELECT :value::VARCHAR, :number::DOUBLE"
      {converted, params} = Yesql.Driver.convert_params(driver, sql, [])

      assert converted == "SELECT $1::VARCHAR, $2::DOUBLE"
      assert params == [:value, :number]
    end

    test "LIST型へのキャスト", %{driver: driver} do
      sql = "SELECT :tags::VARCHAR[] as tag_list"
      {converted, params} = Yesql.Driver.convert_params(driver, sql, [])

      assert converted == "SELECT $1::VARCHAR[] as tag_list"
      assert params == [:tags]
    end
  end

  describe "Ecto ドライバー（$1, $2形式）" do
    setup do
      {:ok, driver} = Yesql.DriverFactory.create(:ecto)
      {:ok, driver: driver}
    end

    test "基本的なパラメータ変換（PostgreSQLと同じ）", %{driver: driver} do
      sql = "SELECT * FROM users WHERE id = :id"
      {converted, params} = Yesql.Driver.convert_params(driver, sql, [])

      assert converted == "SELECT * FROM users WHERE id = $1"
      assert params == [:id]
    end

    test "Ecto.Query互換のパラメータ", %{driver: driver} do
      sql = "INSERT INTO posts (title, body, user_id) VALUES (:title, :body, :user_id)"
      {converted, params} = Yesql.Driver.convert_params(driver, sql, [])

      assert converted == "INSERT INTO posts (title, body, user_id) VALUES ($1, $2, $3)"
      assert params == [:title, :body, :user_id]
    end
  end
end
