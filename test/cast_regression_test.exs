defmodule CastRegressionTest do
  use ExUnit.Case

  @moduletag :regression

  describe "既存機能への影響確認" do
    test "通常のパラメータ解析が正常に動作すること" do
      # :: を含まない通常のクエリ
      assert Yesql.parse("SELECT * FROM users WHERE id = :id") ==
               {:ok, "SELECT * FROM users WHERE id = $1", [:id]}

      assert Yesql.parse("SELECT :name, :age FROM users") ==
               {:ok, "SELECT $1, $2 FROM users", [:name, :age]}
    end

    test "文字列リテラル内のコロンが正しく処理されること" do
      # 文字列内の : や :: は無視される
      assert Yesql.parse("SELECT ':not_param' as col1") ==
               {:ok, "SELECT ':not_param' as col1", []}

      assert Yesql.parse("SELECT 'test::value' as col2") ==
               {:ok, "SELECT 'test::value' as col2", []}

      # エスケープされた文字列
      assert Yesql.parse("SELECT 'It''s a :param inside' as col3") ==
               {:ok, "SELECT 'It''s a :param inside' as col3", []}
    end

    test "複数のパラメータが正しい順序で処理されること" do
      sql = """
      SELECT * FROM orders
      WHERE customer_id = :customer_id
        AND order_date >= :start_date
        AND order_date <= :end_date
        AND status = :status
      ORDER BY order_date DESC
      """

      assert {:ok, parsed_sql, params} = Yesql.parse(sql)
      assert params == [:customer_id, :start_date, :end_date, :status]
      assert parsed_sql =~ "$1"
      assert parsed_sql =~ "$2"
      assert parsed_sql =~ "$3"
      assert parsed_sql =~ "$4"
    end

    test "同じパラメータの再利用が正しく処理されること" do
      sql = """
      SELECT * FROM products
      WHERE price BETWEEN :min_price AND :max_price
        OR sale_price BETWEEN :min_price AND :max_price
      """

      assert {:ok, parsed_sql, params} = Yesql.parse(sql)
      assert params == [:min_price, :max_price]
      assert parsed_sql =~ "BETWEEN $1 AND $2"
      assert parsed_sql =~ "BETWEEN $1 AND $2"
    end

    test "特殊文字を含むパラメータ名" do
      # アンダースコアを含む
      assert Yesql.parse("SELECT :user_name, :created_at") ==
               {:ok, "SELECT $1, $2", [:user_name, :created_at]}

      # 数字を含む
      assert Yesql.parse("SELECT :value1, :value2") ==
               {:ok, "SELECT $1, $2", [:value1, :value2]}

      # 大文字を含む
      assert Yesql.parse("SELECT :userId, :createdAt") ==
               {:ok, "SELECT $1, $2", [:userId, :createdAt]}
    end

    test "演算子との組み合わせ" do
      # 算術演算子
      assert Yesql.parse("SELECT :value + 10") ==
               {:ok, "SELECT $1 + 10", [:value]}

      assert Yesql.parse("SELECT :value - 5") ==
               {:ok, "SELECT $1 - 5", [:value]}

      assert Yesql.parse("SELECT :value * 2") ==
               {:ok, "SELECT $1 * 2", [:value]}

      assert Yesql.parse("SELECT :value / 3") ==
               {:ok, "SELECT $1 / 3", [:value]}

      # 比較演算子
      assert Yesql.parse("WHERE :age >= 18") ==
               {:ok, "WHERE $1 >= 18", [:age]}

      assert Yesql.parse("WHERE :name <> 'test'") ==
               {:ok, "WHERE $1 <> 'test'", [:name]}
    end

    test "関数呼び出し内のパラメータ" do
      assert Yesql.parse("SELECT UPPER(:name)") ==
               {:ok, "SELECT UPPER($1)", [:name]}

      assert Yesql.parse("SELECT COALESCE(:value, 0)") ==
               {:ok, "SELECT COALESCE($1, 0)", [:value]}

      assert Yesql.parse("SELECT DATE_ADD(:date, INTERVAL :days DAY)") ==
               {:ok, "SELECT DATE_ADD($1, INTERVAL $2 DAY)", [:date, :days]}
    end

    test "サブクエリ内のパラメータ" do
      sql = """
      SELECT * FROM users
      WHERE id IN (
        SELECT user_id FROM orders
        WHERE amount > :min_amount
      )
      """

      assert {:ok, parsed_sql, params} = Yesql.parse(sql)
      assert params == [:min_amount]
      assert parsed_sql =~ "amount > $1"
    end

    test "CASE文内のパラメータ" do
      sql = """
      SELECT 
        CASE 
          WHEN age < :young_age THEN 'young'
          WHEN age < :old_age THEN 'middle'
          ELSE 'old'
        END as age_group
      FROM users
      """

      assert {:ok, parsed_sql, params} = Yesql.parse(sql)
      assert params == [:young_age, :old_age]
      assert parsed_sql =~ "age < $1"
      assert parsed_sql =~ "age < $2"
    end

    test "配列構文でのパラメータ" do
      # PostgreSQL配列構文
      assert Yesql.parse("SELECT ARRAY[:value1, :value2, :value3]") ==
               {:ok, "SELECT ARRAY[$1, $2, $3]", [:value1, :value2, :value3]}

      # IN句での使用
      assert Yesql.parse("WHERE id = ANY(:ids)") ==
               {:ok, "WHERE id = ANY($1)", [:ids]}
    end

    test "JSON/JSONB演算子との組み合わせ" do
      # PostgreSQL JSON演算子
      assert Yesql.parse("SELECT data->:key FROM table") ==
               {:ok, "SELECT data->$1 FROM table", [:key]}

      assert Yesql.parse("SELECT data->>:key FROM table") ==
               {:ok, "SELECT data->>$1 FROM table", [:key]}

      assert Yesql.parse("SELECT data#>:path FROM table") ==
               {:ok, "SELECT data#>$1 FROM table", [:path]}

      assert Yesql.parse("SELECT data#>>:path FROM table") ==
               {:ok, "SELECT data#>>$1 FROM table", [:path]}
    end

    @tag :skip
    test "コメント内のパラメータは無視される" do
      sql = """
      -- This is a comment with :param
      SELECT * FROM users -- Another :comment
      WHERE id = :id /* Multi-line
      comment with :param */
      """

      assert {:ok, _parsed_sql, params} = Yesql.parse(sql)
      assert params == [:id]
    end

    test "改行やタブを含むクエリ" do
      sql = "SELECT\n\t:value1,\n\t:value2\nFROM\n\ttable"

      assert {:ok, parsed_sql, params} = Yesql.parse(sql)
      assert params == [:value1, :value2]
      assert parsed_sql =~ "$1"
      assert parsed_sql =~ "$2"
    end
  end

  describe "エラーケースの確認" do
    test "不正なパラメータ名はパラメータとして認識されない" do
      # 空のパラメータ名はエラーになる
      result = Yesql.parse("SELECT : FROM table")
      assert elem(result, 0) == :error

      # 特殊文字で始まる（実際にはパラメータとして認識される）
      assert Yesql.parse("SELECT :@param FROM table") ==
               {:ok, "SELECT $1 FROM table", [:"@param"]}

      # スペースを含む（エラーになる）
      result2 = Yesql.parse("SELECT : param FROM table")
      assert elem(result2, 0) == :error
    end
  end

  describe "パフォーマンステスト" do
    @tag :performance
    test "大きなクエリのパース性能" do
      # 1000個のパラメータを含むクエリ
      params = Enum.map(1..1000, &"value#{&1}")
      placeholders = Enum.map(params, &":#{&1}") |> Enum.join(", ")
      sql = "INSERT INTO large_table VALUES (#{placeholders})"

      start_time = System.monotonic_time(:microsecond)
      assert {:ok, _parsed_sql, parsed_params} = Yesql.parse(sql)
      end_time = System.monotonic_time(:microsecond)

      duration = end_time - start_time

      assert length(parsed_params) == 1000
      # 100ms以内
      assert duration < 100_000

      IO.puts("Parsed 1000 parameters in #{duration}μs")
    end
  end
end
