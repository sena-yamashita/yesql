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

        # Ectoマイグレーションでテーブルが作成されるはず
        # CI環境でマイグレーションが実行されていない場合の対応はtest_helper.exsで行う

        [conn: conn, driver: :postgrex]

      _ ->
        {:ok, skip: true}
    end
  end

  setup context do
    # 各テストの前にテーブルをクリア
    case context do
      %{conn: conn} when not is_nil(conn) ->
        Postgrex.query!(conn, "DELETE FROM batch_test", [])
        :ok

      _ ->
        :ok
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
      {:ok, result} = Postgrex.query(conn, "SELECT name, value FROM batch_test ORDER BY id", [])
      assert result.rows == [["Item1", 100], ["Item2", 200], ["Item3", 300]]
    end

    test "トランザクション内でのエラー処理", %{conn: conn, driver: driver} do
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
      named_queries = %{
        insert_alice: {"INSERT INTO batch_test (name, value) VALUES ($1, $2)", ["Alice", 100]},
        insert_bob: {"INSERT INTO batch_test (name, value) VALUES ($1, $2)", ["Bob", 200]},
        count_all: {"SELECT COUNT(*) as count FROM batch_test", []}
      }

      # CI環境ではトランザクションを無効にする
      transaction_opt = if System.get_env("CI"), do: false, else: true

      # デバッグ用出力
      if System.get_env("CI") || System.get_env("DEBUG_BATCH_TEST") do
        IO.puts("\n=== BatchTest Debug Info ===")
        IO.puts("CI: #{System.get_env("CI")}")
        IO.puts("Transaction opt: #{transaction_opt}")
        IO.puts("Named queries: #{inspect(named_queries)}")

        # バッチ実行前のテーブル状態
        {:ok, before_count} = Postgrex.query(conn, "SELECT COUNT(*) as count FROM batch_test", [])
        IO.puts("Records before batch: #{inspect(before_count.rows)}")

        # 各クエリを個別に実行してデバッグ（トランザクション内でロールバック）
        IO.puts("\n=== Individual query execution (will rollback) ===")
        Postgrex.query!(conn, "BEGIN", [])

        Enum.each(Map.to_list(named_queries), fn {name, {query, params}} ->
          IO.puts("\nExecuting #{name}: #{query}")
          IO.puts("Params: #{inspect(params)}")

          case Postgrex.query(conn, query, params) do
            {:ok, result} ->
              IO.puts("Success: rows_affected=#{result.num_rows}")

              if name == :count_all do
                IO.puts("Count result: #{inspect(result.rows)}")
              end

            {:error, error} ->
              IO.puts("Error: #{inspect(error)}")
          end
        end)

        # トランザクション内のカウント
        {:ok, tx_count} = Postgrex.query(conn, "SELECT COUNT(*) as count FROM batch_test", [])
        IO.puts("\nRecords in transaction: #{inspect(tx_count.rows)}")

        # ロールバック
        Postgrex.query!(conn, "ROLLBACK", [])
        IO.puts("Rolled back debug transaction")

        # ロールバック後のカウント
        {:ok, after_rollback} =
          Postgrex.query(conn, "SELECT COUNT(*) as count FROM batch_test", [])

        IO.puts("Records after rollback: #{inspect(after_rollback.rows)}")
        IO.puts("=== End Individual execution ===")
      end

      # バッチ実行
      {:ok, results} =
        Batch.execute_named(named_queries,
          driver: driver,
          conn: conn,
          transaction: transaction_opt
        )

      # デバッグ用出力
      if System.get_env("CI") || System.get_env("DEBUG_BATCH_TEST") do
        IO.puts("\n=== Batch execution results ===")
        IO.inspect(results, label: "Batch results")

        # バッチ実行後のカウント
        {:ok, batch_count} = Postgrex.query(conn, "SELECT COUNT(*) as count FROM batch_test", [])
        IO.puts("Records after batch: #{inspect(batch_count.rows)}")

        # 全レコードを表示
        {:ok, all_records} = Postgrex.query(conn, "SELECT * FROM batch_test", [])
        IO.puts("All records: #{inspect(all_records.rows)}")
        IO.puts("=== End Debug Info ===")
      end

      # 結果にアクセス
      assert results.count_all == [%{count: 2}]
    end

    test "名前付きクエリのエラー処理", %{conn: conn, driver: driver} do
      # 順序を保証するために、明示的に順序付けされたクエリを使用
      # (MapのキーはElixirで自動的にソートされるため、アルファベット順になる)
      named_queries = %{
        a_valid: {"INSERT INTO batch_test (name, value) VALUES ($1, $2)", ["Valid", 100]},
        b_invalid:
          {"INSERT INTO batch_test (name, value) VALUES ($1, $2)", ["Invalid", "not_a_number"]},
        c_never_executed: {"INSERT INTO batch_test (name, value) VALUES ($1, $2)", ["Never", 300]}
      }

      {:error, _reason, partial_results} =
        Batch.execute_named(named_queries,
          driver: driver,
          conn: conn
        )

      # 最初のクエリ(a_valid)のみ結果に含まれる
      assert Map.has_key?(partial_results, :a_valid)
      refute Map.has_key?(partial_results, :b_invalid)
      refute Map.has_key?(partial_results, :c_never_executed)
    end
  end

  describe "パイプライン実行" do
    test "前の結果を使った連鎖実行", %{conn: conn, driver: driver} do
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

      # 最後のクエリの結果を確認（結果は実行順）
      count_result = List.last(results)
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
