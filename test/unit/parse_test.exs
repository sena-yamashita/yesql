defmodule Yesql.Unit.ParseTest do
  use ExUnit.Case, async: true

  @moduletag :unit

  describe "parse/1" do
    import Yesql, only: [parse: 1]

    test "シンプルなSELECT文" do
      assert parse("SELECT * FROM users") == {:ok, "SELECT * FROM users", []}
    end

    test "パラメータ1つ" do
      assert parse("SELECT * FROM users WHERE id = :id") ==
               {:ok, "SELECT * FROM users WHERE id = $1", [:id]}
    end

    test "複数のパラメータ" do
      assert parse("SELECT * FROM users WHERE name = :name AND age > :age") ==
               {:ok, "SELECT * FROM users WHERE name = $1 AND age > $2", [:name, :age]}
    end

    test "同じパラメータの再利用" do
      assert parse("SELECT * FROM users WHERE age > :age OR age < :age") ==
               {:ok, "SELECT * FROM users WHERE age > $1 OR age < $1", [:age]}
    end

    test "PostgreSQL :: キャスト構文" do
      assert parse("SELECT :value::text") ==
               {:ok, "SELECT $1::text", [:value]}
    end

    test "複雑なPostgreSQLキャスト" do
      assert parse("SELECT :id::bigint, :data::jsonb, :tags::text[]") ==
               {:ok, "SELECT $1::bigint, $2::jsonb, $3::text[]", [:id, :data, :tags]}
    end

    test "CAST関数形式" do
      assert parse("SELECT CAST(:value AS INTEGER)") ==
               {:ok, "SELECT CAST($1 AS INTEGER)", [:value]}
    end

    test "文字列内のコロン" do
      assert parse("SELECT ':not_a_param', :real_param") ==
               {:ok, "SELECT ':not_a_param', $1", [:real_param]}
    end

    test "改行を含むクエリ" do
      sql = """
      SELECT *
      FROM users
      WHERE id = :id
      """

      {:ok, parsed, params} = parse(sql)
      assert params == [:id]
      assert parsed =~ "$1"
    end

    test "コメントを含むクエリ" do
      sql = """
      -- ユーザー検索
      SELECT * FROM users
      WHERE id = :id -- IDで検索
      """

      {:ok, _parsed, params} = parse(sql)
      assert params == [:id]
    end
  end

  describe "パラメータ変換パターン" do
    import Yesql, only: [parse: 1]

    test "INSERT文" do
      assert parse("INSERT INTO users (name, age) VALUES (:name, :age)") ==
               {:ok, "INSERT INTO users (name, age) VALUES ($1, $2)", [:name, :age]}
    end

    test "UPDATE文" do
      assert parse("UPDATE users SET name = :name WHERE id = :id") ==
               {:ok, "UPDATE users SET name = $1 WHERE id = $2", [:name, :id]}
    end

    test "DELETE文" do
      assert parse("DELETE FROM users WHERE id = :id") ==
               {:ok, "DELETE FROM users WHERE id = $1", [:id]}
    end

    test "JOIN文" do
      sql = """
      SELECT u.*, p.title
      FROM users u
      JOIN posts p ON u.id = p.user_id
      WHERE u.age > :min_age AND p.published = :published
      """

      {:ok, parsed, params} = parse(sql)
      assert params == [:min_age, :published]
      assert parsed =~ "$1"
      assert parsed =~ "$2"
    end
  end
end
