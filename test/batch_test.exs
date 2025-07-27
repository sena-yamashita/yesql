defmodule BatchTest do
  use ExUnit.Case, async: false

  alias Yesql.{Batch, Transaction}

  # 環境変数でテストを制御
  @moduletag :batch

  setup_all do
    # PostgreSQLでテスト（デフォルト）
    case System.get_env("BATCH_TEST_DRIVER", "postgrex") do
      "postgrex" ->
        {:ok, conn} =
          Postgrex.start_link(
            hostname: System.get_env("POSTGRES_HOST", "localhost"),
            username: System.get_env("POSTGRES_USER", "postgres"),
            password: System.get_env("POSTGRES_PASSWORD", "postgres"),
            database: System.get_env("POSTGRES_DATABASE", "yesql_test"),
            port: String.to_integer(System.get_env("POSTGRES_PORT", "5432"))
          )

        # テーブル作成
        Postgrex.query!(conn, "DROP TABLE IF EXISTS batch_test CASCADE", [])

        Postgrex.query!(
          conn,
          """
          CREATE TABLE batch_test (
            id SERIAL PRIMARY KEY,
            name VARCHAR(255),
            value INTEGER,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
          )
          """,
          []
        )

        [conn: conn, driver: :postgrex]

      _ ->
        {:ok, skip: true}
    end
  end

  describe "バッチクエリ実行" do
    test "複数クエリの成功実行", %{conn: conn, driver: driver} do
      queries = [
        {"INSERT INTO batch_test (name, value) VALUES ($1, $2)", ["Item1", 100]},
        {"INSERT INTO batch_test (name, value) VALUES ($1, $2)", ["Item2", 200]},
        {"INSERT INTO batch_test (name, value) VALUES ($1, $2)", ["Item3", 300]}
      ]

      {:ok, results} = Batch.execute(queries, driver: driver, conn: conn)

      assert length(results) == 3

      # 結果を確認
      {:ok, %{rows: rows}} =
        Postgrex.query(conn, "SELECT name, value FROM batch_test ORDER BY id", [])

      assert rows == [["Item1", 100], ["Item2", 200], ["Item3", 300]]
    end

    test "トランザクション内でのエラー処理", %{conn: conn, driver: driver} do
      # テーブルをクリア
      Postgrex.query!(conn, "TRUNCATE batch_test", [])

      queries = [
        {"INSERT INTO batch_test (name, value) VALUES ($1, $2)", ["Valid", 100]},
        # エラー
        {"INSERT INTO batch_test (name, value) VALUES ($1, $2)", ["Invalid", "not_a_number"]},
        {"INSERT INTO batch_test (name, value) VALUES ($1, $2)", ["Never", 300]}
      ]

      {:error, _reason, partial_results} =
        Batch.execute(queries,
          driver: driver,
          conn: conn,
          transaction: true
        )

      # 最初のクエリのみ成功したが、トランザクションでロールバック
      assert length(partial_results) == 1

      # データがロールバックされていることを確認
      {:ok, %{rows: rows}} = Postgrex.query(conn, "SELECT COUNT(*) FROM batch_test", [])
      assert rows == [[0]]
    end

    test "トランザクションなしでのエラー処理", %{conn: conn, driver: driver} do
      # テーブルをクリア
      Postgrex.query!(conn, "TRUNCATE batch_test", [])

      queries = [
        {"INSERT INTO batch_test (name, value) VALUES ($1, $2)", ["Valid1", 100]},
        # エラー
        {"INSERT INTO batch_test (name, value) VALUES ($1, $2)", ["Invalid", "not_a_number"]},
        {"INSERT INTO batch_test (name, value) VALUES ($1, $2)", ["Never", 300]}
      ]

      {:error, _reason, partial_results} =
        Batch.execute(queries,
          driver: driver,
          conn: conn,
          transaction: false
        )

      assert length(partial_results) == 1

      # 最初のクエリは成功してコミットされている
      {:ok, %{rows: rows}} = Postgrex.query(conn, "SELECT COUNT(*) FROM batch_test", [])
      assert rows == [[1]]
    end

    test "エラー時の続行オプション", %{conn: conn, driver: driver} do
      # テーブルをクリア
      Postgrex.query!(conn, "TRUNCATE batch_test", [])

      queries = [
        {"INSERT INTO batch_test (name, value) VALUES ($1, $2)", ["Valid1", 100]},
        # エラー
        {"INSERT INTO batch_test (name, value) VALUES ($1, $2)", ["Invalid", "not_a_number"]},
        {"INSERT INTO batch_test (name, value) VALUES ($1, $2)", ["Valid2", 300]}
      ]

      {:ok, results} =
        Batch.execute(queries,
          driver: driver,
          conn: conn,
          transaction: false,
          on_error: :continue
        )

      # 全てのクエリが実行される
      assert length(results) == 3

      # 2番目の結果はエラー
      assert match?({:error, _}, Enum.at(results, 1))

      # 有効なデータは挿入されている
      {:ok, %{rows: rows}} = Postgrex.query(conn, "SELECT name FROM batch_test ORDER BY id", [])
      assert rows == [["Valid1"], ["Valid2"]]
    end
  end

  describe "名前付きバッチクエリ" do
    test "名前付きクエリの実行", %{conn: conn, driver: driver} do
      # テーブルをクリア
      Postgrex.query!(conn, "TRUNCATE batch_test", [])

      named_queries = %{
        insert_alice: {"INSERT INTO batch_test (name, value) VALUES ($1, $2)", ["Alice", 100]},
        insert_bob: {"INSERT INTO batch_test (name, value) VALUES ($1, $2)", ["Bob", 200]},
        count_all: {"SELECT COUNT(*) as count FROM batch_test", []}
      }

      {:ok, results} = Batch.execute_named(named_queries, driver: driver, conn: conn)

      # 結果にアクセス
      assert results.count_all == [%{count: 2}]
    end

    test "名前付きクエリのエラー処理", %{conn: conn, driver: driver} do
      named_queries = %{
        valid: {"INSERT INTO batch_test (name, value) VALUES ($1, $2)", ["Valid", 100]},
        invalid:
          {"INSERT INTO batch_test (name, value) VALUES ($1, $2)", ["Invalid", "not_a_number"]},
        never_executed: {"INSERT INTO batch_test (name, value) VALUES ($1, $2)", ["Never", 300]}
      }

      {:error, _reason, partial_results} =
        Batch.execute_named(named_queries,
          driver: driver,
          conn: conn
        )

      # 最初のクエリのみ結果に含まれる
      assert Map.has_key?(partial_results, :valid)
      refute Map.has_key?(partial_results, :invalid)
      refute Map.has_key?(partial_results, :never_executed)
    end
  end

  describe "パイプライン実行" do
    test "前の結果を使った連鎖実行", %{conn: conn, driver: driver} do
      # テーブルをクリア
      Postgrex.query!(conn, "TRUNCATE batch_test", [])

      pipeline = [
        # 最初のクエリ
        fn _ ->
          {"INSERT INTO batch_test (name, value) VALUES ($1, $2) RETURNING id, name",
           ["Pipeline1", 100]}
        end,

        # 前の結果のIDを使う
        fn [%{id: prev_id}] ->
          {"INSERT INTO batch_test (name, value) VALUES ($1, $2)",
           ["Pipeline2_ref_#{prev_id}", 200]}
        end,

        # カウントを取得
        fn _ ->
          {"SELECT COUNT(*) as count FROM batch_test", []}
        end
      ]

      {:ok, results} = Batch.pipeline(pipeline, driver: driver, conn: conn)

      assert length(results) == 3

      # 最後のクエリの結果を確認
      [count_result | _] = results
      assert count_result == [%{count: 2}]
    end

    test "パイプラインでのエラー処理", %{conn: conn, driver: driver} do
      pipeline = [
        fn _ ->
          {"INSERT INTO batch_test (name, value) VALUES ($1, $2) RETURNING id", ["Valid", 100]}
        end,
        fn _ ->
          # エラー
          {"INSERT INTO batch_test (name, value) VALUES ($1, $2)", ["Invalid", "not_a_number"]}
        end,
        fn _ ->
          # 実行されない
          {"SELECT COUNT(*) FROM batch_test", []}
        end
      ]

      {:error, _reason, partial_results} = Batch.pipeline(pipeline, driver: driver, conn: conn)

      # 最初のクエリのみ成功
      assert length(partial_results) == 1
    end
  end

  describe "トランザクション管理の改善" do
    test "分離レベルの設定", %{conn: conn, driver: driver} do
      result =
        Transaction.transaction(
          conn,
          fn conn ->
            # トランザクション内でクエリを実行
            Postgrex.query!(conn, "INSERT INTO batch_test (name, value) VALUES ($1, $2)", [
              "Isolated",
              100
            ])

            :ok
          end,
          driver: driver,
          isolation_level: :serializable
        )

      assert result == {:ok, :ok}
    end

    test "明示的なロールバック", %{conn: conn, driver: driver} do
      # テーブルをクリア
      Postgrex.query!(conn, "TRUNCATE batch_test", [])

      result =
        Transaction.transaction(
          conn,
          fn conn ->
            Postgrex.query!(conn, "INSERT INTO batch_test (name, value) VALUES ($1, $2)", [
              "Rollback",
              100
            ])

            # 明示的にロールバック
            Transaction.rollback(:manual_rollback)
          end,
          driver: driver
        )

      assert result == {:error, {:rollback, :manual_rollback}}

      # データがロールバックされていることを確認
      {:ok, %{rows: [[count]]}} = Postgrex.query(conn, "SELECT COUNT(*) FROM batch_test", [])
      assert count == 0
    end

    test "セーブポイントの使用", %{conn: conn, driver: driver} do
      # テーブルをクリア
      Postgrex.query!(conn, "TRUNCATE batch_test", [])

      result =
        Transaction.transaction(
          conn,
          fn conn ->
            # 最初の挿入
            Postgrex.query!(conn, "INSERT INTO batch_test (name, value) VALUES ($1, $2)", [
              "First",
              100
            ])

            # セーブポイント作成
            {:ok, _} = Transaction.savepoint(conn, "sp1", driver: driver)

            # 2番目の挿入
            Postgrex.query!(conn, "INSERT INTO batch_test (name, value) VALUES ($1, $2)", [
              "Second",
              200
            ])

            # セーブポイントまでロールバック
            {:ok, _} = Transaction.rollback_to_savepoint(conn, "sp1", driver: driver)

            # 3番目の挿入
            Postgrex.query!(conn, "INSERT INTO batch_test (name, value) VALUES ($1, $2)", [
              "Third",
              300
            ])

            :ok
          end,
          driver: driver
        )

      assert result == {:ok, :ok}

      # FirstとThirdのみが存在することを確認
      {:ok, %{rows: rows}} = Postgrex.query(conn, "SELECT name FROM batch_test ORDER BY id", [])
      assert rows == [["First"], ["Third"]]
    end
  end
end
