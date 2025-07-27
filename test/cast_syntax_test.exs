defmodule CastSyntaxTest do
  use ExUnit.Case
  doctest Yesql

  describe "データベースキャスト構文のサポート" do
    test "PostgreSQL :: キャスト構文" do
      # 基本的な型キャスト
      assert Yesql.parse("SELECT :value::text") ==
               {:ok, "SELECT $1::text", [:value]}

      assert Yesql.parse("SELECT :id::integer, :data::jsonb") ==
               {:ok, "SELECT $1::integer, $2::jsonb", [:id, :data]}

      # 複雑な例
      assert Yesql.parse("SELECT :tag::jsonb, data->>'name'::text FROM users") ==
               {:ok, "SELECT $1::jsonb, data->>'name'::text FROM users", [:tag]}

      # 配列キャスト
      assert Yesql.parse("SELECT :ids::integer[]") ==
               {:ok, "SELECT $1::integer[]", [:ids]}

      # カスタム型へのキャスト
      assert Yesql.parse("SELECT :status::status_enum") ==
               {:ok, "SELECT $1::status_enum", [:status]}
    end

    test "式の中での :: キャスト" do
      # 演算子と組み合わせ
      assert Yesql.parse("SELECT :value::integer + 10") ==
               {:ok, "SELECT $1::integer + 10", [:value]}

      # 関数呼び出しの中で
      assert Yesql.parse("SELECT array_agg(:id::text)") ==
               {:ok, "SELECT array_agg($1::text)", [:id]}

      # WHERE句での使用
      assert Yesql.parse("WHERE :date::date > CURRENT_DATE") ==
               {:ok, "WHERE $1::date > CURRENT_DATE", [:date]}
    end

    test "JSONBキャスト関連の構文" do
      # JSONB演算子と組み合わせ
      assert Yesql.parse("SELECT data @> :filter::jsonb") ==
               {:ok, "SELECT data @> $1::jsonb", [:filter]}

      # JSONB配列要素へのキャスト
      assert Yesql.parse("SELECT data->'tags' @> :tag::jsonb") ==
               {:ok, "SELECT data->'tags' @> $1::jsonb", [:tag]}

      # 複数のJSONB操作
      assert Yesql.parse("SELECT :data::jsonb || :update::jsonb") ==
               {:ok, "SELECT $1::jsonb || $2::jsonb", [:data, :update]}
    end

    test "他のデータベースのキャスト構文（CAST関数）" do
      # 標準SQLのCAST構文
      assert Yesql.parse("SELECT CAST(:value AS INTEGER)") ==
               {:ok, "SELECT CAST($1 AS INTEGER)", [:value]}

      # ネストしたCAST
      assert Yesql.parse("SELECT CAST(CAST(:value AS TEXT) AS INTEGER)") ==
               {:ok, "SELECT CAST(CAST($1 AS TEXT) AS INTEGER)", [:value]}
    end

    test ":: を含む文字列リテラル" do
      # 文字列内の :: は無視される
      assert Yesql.parse("SELECT 'test::value' FROM dual") ==
               {:ok, "SELECT 'test::value' FROM dual", []}

      # パラメータと文字列の組み合わせ
      assert Yesql.parse("SELECT :id, 'prefix::suffix'") ==
               {:ok, "SELECT $1, 'prefix::suffix'", [:id]}
    end

    test "エッジケース" do
      # :: の直後に空白
      assert Yesql.parse("SELECT :value:: integer") ==
               {:ok, "SELECT $1:: integer", [:value]}

      # 複数の :: （エラーになるSQL、でもパースは通る）
      assert Yesql.parse("SELECT :value::::text") ==
               {:ok, "SELECT $1::::text", [:value]}

      # パラメータ名に数字を含む場合
      assert Yesql.parse("SELECT :value1::integer, :value2::text") ==
               {:ok, "SELECT $1::integer, $2::text", [:value1, :value2]}
    end

    test "実際のPostgreSQLクエリ例" do
      # テーブル作成時の型キャスト使用例
      sql = """
      INSERT INTO users (data, tags, created_at)
      VALUES (:user_data::jsonb, :tags::text[], :created::timestamptz)
      RETURNING id, data->>'name' as name
      """

      assert {:ok, parsed_sql, params} = Yesql.parse(sql)
      assert params == [:user_data, :tags, :created]
      assert parsed_sql =~ "$1::jsonb"
      assert parsed_sql =~ "$2::text[]"
      assert parsed_sql =~ "$3::timestamptz"
    end

    test "DuckDBの :: キャスト構文" do
      # DuckDBもPostgreSQL互換の :: をサポート
      assert Yesql.parse("SELECT :amount::DECIMAL(10,2)") ==
               {:ok, "SELECT $1::DECIMAL(10,2)", [:amount]}

      assert Yesql.parse("SELECT :date::DATE, :time::TIME") ==
               {:ok, "SELECT $1::DATE, $2::TIME", [:date, :time]}
    end

    test "複雑な実例" do
      # WITH句を含む複雑なクエリ
      sql = """
      WITH user_filter AS (
        SELECT * FROM users 
        WHERE data @> :filter::jsonb
          AND created_at > :since::timestamptz
      )
      SELECT id, data->>'name'::text as name,
             (data->>'age')::integer as age,
             tags::text[] as tags
      FROM user_filter
      WHERE (data->>'active')::boolean = true
      """

      assert {:ok, parsed_sql, params} = Yesql.parse(sql)
      assert params == [:filter, :since]
      assert parsed_sql =~ "$1::jsonb"
      assert parsed_sql =~ "$2::timestamptz"
      assert parsed_sql =~ "::text as name"
      assert parsed_sql =~ "::integer as age"
      assert parsed_sql =~ "::boolean = true"
    end
  end
end
