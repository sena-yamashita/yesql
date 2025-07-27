defmodule YesqlMSSQLTest do
  use ExUnit.Case

  # MSSQLテストタグ
  @moduletag :mssql

  defmodule Queries do
    use Yesql, driver: :mssql

    Yesql.defquery("test/sql/mssql/select_users_by_name.sql")
    Yesql.defquery("test/sql/mssql/select_users_by_age_range.sql")
    Yesql.defquery("test/sql/mssql/insert_user.sql")
  end

  setup_all do
    # CI環境では自動的にMSSQLテストを実行
    if System.get_env("CI") || System.get_env("MSSQL_TEST") == "true" do
      case TestHelper.new_mssql_connection(%{module: __MODULE__}) do
        {:ok, ctx} ->
          # テーブル作成
          setup_database(ctx.mssql)
          {:ok, mssql: ctx.mssql}

        _ ->
          IO.puts("MSSQLテストをスキップします - 接続失敗")
          {:ok, skip: true}
      end
    else
      IO.puts("MSSQLテストをスキップします。実行するには MSSQL_TEST=true を設定してください。")
      {:ok, skip: true}
    end
  end

  setup context do
    if context[:conn] do
      # 各テストの前にテーブルをクリア
      Tds.query!(context[:conn], "TRUNCATE TABLE users", [])

      # テストデータを挿入
      Tds.query!(
        context[:conn],
        "INSERT INTO users (id, name, age) VALUES (1, 'Alice', 25), (2, 'Bob', 30), (3, 'Charlie', 35)",
        []
      )
    end

    :ok
  end

  describe "MSSQLドライバー" do
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
      %{rows: [[count]]} = Tds.query!(conn, "SELECT COUNT(*) FROM users WHERE name = 'David'", [])
      assert count == 1
    end

    test "パラメータが正しい順序で@p1, @p2...に置換される", %{conn: _conn} do
      # 複雑なクエリでパラメータの順序をテスト
      sql = "SELECT * FROM users WHERE age > :min_age AND name = :name AND age < :max_age"
      driver = %Yesql.Driver.MSSQL{}

      {converted_sql, param_order} = Yesql.Driver.convert_params(driver, sql, [])

      assert converted_sql == "SELECT * FROM users WHERE age > @p1 AND name = @p2 AND age < @p3"
      assert param_order == [:min_age, :name, :max_age]
    end

    test "重複するパラメータが正しく処理される", %{conn: _conn} do
      sql = "SELECT * FROM users WHERE name = :name OR nickname = :name"
      driver = %Yesql.Driver.MSSQL{}

      {converted_sql, param_order} = Yesql.Driver.convert_params(driver, sql, [])

      assert converted_sql == "SELECT * FROM users WHERE name = @p1 OR nickname = @p1"
      assert param_order == [:name]
    end
  end

  describe "エラーハンドリング" do
    test "無効なクエリはエラーを返す", %{conn: conn} do
      # 存在しないテーブルへのクエリ
      {:error, %Tds.Error{}} = Tds.query(conn, "SELECT * FROM nonexistent_table", [])
    end
  end

  # テストデータベースのセットアップ
  defp setup_database(conn) do
    # テーブルが存在する場合は削除
    try do
      Tds.query!(conn, "DROP TABLE users", [])
    rescue
      _ -> :ok
    end

    # テーブル作成
    Tds.query!(conn, """
      CREATE TABLE users (
        id INT PRIMARY KEY,
        name NVARCHAR(255) NOT NULL,
        age INT NOT NULL
      )
    """, [])
  end
end
