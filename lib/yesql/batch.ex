defmodule Yesql.Batch do
  @moduledoc """
  バッチクエリ実行のサポートモジュール

  複数のクエリを効率的に実行するための機能を提供します。
  """

  alias Yesql.{Driver, DriverFactory}

  @doc """
  複数のクエリを一括実行する

  ## パラメータ

    * `queries` - クエリのリスト。各クエリは `{sql, params}` のタプル
    * `opts` - オプション
      * `:driver` - 使用するドライバー（必須）
      * `:conn` - データベース接続（必須）
      * `:transaction` - トランザクション内で実行するか（デフォルト: true）
      * `:on_error` - エラー時の動作（:stop | :continue、デフォルト: :stop）

  ## 戻り値

    * `{:ok, results}` - 全てのクエリが成功した場合
    * `{:error, reason, partial_results}` - エラーが発生した場合

  ## 例

      queries = [
        {"INSERT INTO users (name, age) VALUES ($1, $2)", ["Alice", 25]},
        {"INSERT INTO users (name, age) VALUES ($1, $2)", ["Bob", 30]},
        {"UPDATE stats SET user_count = user_count + 2", []}
      ]
      
      {:ok, results} = Yesql.Batch.execute(queries,
        driver: :postgrex,
        conn: conn,
        transaction: true
      )
  """
  def execute(queries, opts) when is_list(queries) do
    driver_name = Keyword.fetch!(opts, :driver)
    conn = Keyword.fetch!(opts, :conn)
    transaction = Keyword.get(opts, :transaction, true)
    on_error = Keyword.get(opts, :on_error, :stop)

    with {:ok, driver} <- DriverFactory.create(driver_name) do
      if transaction && supports_transactions?(driver_name) do
        execute_in_transaction(driver, conn, queries, on_error)
      else
        execute_without_transaction(driver, conn, queries, on_error)
      end
    end
  end

  @doc """
  名前付きクエリを一括実行する

  ## パラメータ

    * `named_queries` - 名前付きクエリのマップ
    * `opts` - オプション（`execute/2`と同じ）

  ## 戻り値

    * `{:ok, results_map}` - 名前をキーとした結果のマップ
    * `{:error, reason, partial_results_map}` - エラーが発生した場合

  ## 例

      named_queries = %{
        create_user: {"INSERT INTO users (name) VALUES ($1) RETURNING id", ["Alice"]},
        create_profile: {"INSERT INTO profiles (user_id, bio) VALUES ($1, $2)", [1, "Bio"]},
        update_stats: {"UPDATE stats SET user_count = user_count + 1", []}
      }
      
      {:ok, results} = Yesql.Batch.execute_named(named_queries,
        driver: :postgrex,
        conn: conn
      )
      
      user_id = results.create_user |> hd() |> Map.get(:id)
  """
  def execute_named(named_queries, opts) when is_map(named_queries) do
    # 名前とクエリを分離
    names = Map.keys(named_queries)
    queries = Enum.map(names, &Map.get(named_queries, &1))

    case execute(queries, opts) do
      {:ok, results} ->
        # 結果を名前付きマップに変換
        results_map =
          names
          |> Enum.zip(results)
          |> Enum.into(%{})

        {:ok, results_map}

      {:error, reason, partial_results} ->
        # 部分的な結果も名前付きマップに変換
        partial_map =
          names
          |> Enum.take(length(partial_results))
          |> Enum.zip(partial_results)
          |> Enum.into(%{})

        {:error, reason, partial_map}
    end
  end

  @doc """
  パイプライン形式でクエリを実行する

  前のクエリの結果を次のクエリのパラメータとして使用できます。

  ## 例

      pipeline = [
        # ユーザーを作成してIDを取得
        fn _ ->
          {"INSERT INTO users (name) VALUES ($1) RETURNING id", ["Alice"]}
        end,
        
        # 前の結果のIDを使ってプロファイルを作成
        fn [%{id: user_id}] ->
          {"INSERT INTO profiles (user_id, bio) VALUES ($1, $2)", [user_id, "Bio"]}
        end,
        
        # 統計を更新
        fn _ ->
          {"UPDATE stats SET user_count = user_count + 1", []}
        end
      ]
      
      {:ok, results} = Yesql.Batch.pipeline(pipeline,
        driver: :postgrex,
        conn: conn
      )
  """
  def pipeline(pipeline_fns, opts) when is_list(pipeline_fns) do
    driver_name = Keyword.fetch!(opts, :driver)
    conn = Keyword.fetch!(opts, :conn)

    with {:ok, driver} <- DriverFactory.create(driver_name) do
      execute_pipeline(driver, conn, pipeline_fns, [])
    end
  end

  # プライベート関数

  defp execute_in_transaction(driver, conn, queries, on_error) do
    # ドライバー固有のトランザクション開始
    case begin_transaction(driver, conn) do
      {:ok, _} ->
        case execute_queries(driver, conn, queries, on_error, []) do
          {:ok, results} ->
            case commit_transaction(driver, conn) do
              {:ok, _} ->
                {:ok, results}

              error ->
                rollback_transaction(driver, conn)
                error
            end

          {:error, reason, partial_results} ->
            rollback_transaction(driver, conn)
            {:error, reason, partial_results}
        end

      error ->
        error
    end
  end

  defp execute_without_transaction(driver, conn, queries, on_error) do
    execute_queries(driver, conn, queries, on_error, [])
  end

  defp execute_queries(_driver, _conn, [], _on_error, results) do
    {:ok, Enum.reverse(results)}
  end

  defp execute_queries(driver, conn, [{sql, params} | rest], on_error, results) do
    case Driver.execute(driver, conn, sql, params) do
      {:ok, result} ->
        processed_result =
          case Driver.process_result(driver, {:ok, result}) do
            {:ok, data} -> data
            _ -> result
          end

        execute_queries(driver, conn, rest, on_error, [processed_result | results])

      {:error, _} = error when on_error == :continue ->
        # エラーを記録して続行
        execute_queries(driver, conn, rest, on_error, [error | results])

      {:error, reason} ->
        # エラーで停止
        {:error, reason, Enum.reverse(results)}
    end
  end

  defp execute_pipeline(_driver, _conn, [], results) do
    {:ok, Enum.reverse(results)}
  end

  defp execute_pipeline(driver, conn, [fn_head | fn_tail], results) do
    # 前の結果を使って次のクエリを生成
    last_result = List.first(results)
    {sql, params} = fn_head.(last_result)

    case Driver.execute(driver, conn, sql, params) do
      {:ok, result} ->
        processed_result =
          case Driver.process_result(driver, {:ok, result}) do
            {:ok, data} -> data
            _ -> result
          end

        execute_pipeline(driver, conn, fn_tail, [processed_result | results])

      {:error, reason} ->
        {:error, reason, Enum.reverse(results)}
    end
  end

  # トランザクション管理

  defp supports_transactions?(driver_name) do
    # DuckDBは自動コミットモード
    driver_name not in [:duckdb]
  end

  if Code.ensure_loaded?(Postgrex) do
    defp begin_transaction(%Yesql.Driver.Postgrex{}, conn) do
      Postgrex.query(conn, "BEGIN", [])
    end
  else
    defp begin_transaction(%Yesql.Driver.Postgrex{}, _conn) do
      {:error, :driver_not_loaded}
    end
  end

  if Code.ensure_loaded?(MyXQL) do
    defp begin_transaction(%Yesql.Driver.MySQL{}, conn) do
      MyXQL.query(conn, "START TRANSACTION", [])
    end
  else
    defp begin_transaction(%Yesql.Driver.MySQL{}, _conn) do
      {:error, :driver_not_loaded}
    end
  end

  if Code.ensure_loaded?(Tds) do
    defp begin_transaction(%Yesql.Driver.MSSQL{}, conn) do
      Tds.query(conn, "BEGIN TRANSACTION", [])
    end
  else
    defp begin_transaction(%Yesql.Driver.MSSQL{}, _conn) do
      {:error, :driver_not_loaded}
    end
  end

  if Code.ensure_loaded?(Jamdb.Oracle) do
    defp begin_transaction(%Yesql.Driver.Oracle{}, _conn) do
      # Oracleは自動的にトランザクションを開始
      {:ok, :auto}
    end
  else
    defp begin_transaction(%Yesql.Driver.Oracle{}, _conn) do
      {:error, :driver_not_loaded}
    end
  end

  if Code.ensure_loaded?(Exqlite) do
    defp begin_transaction(%Yesql.Driver.SQLite{}, conn) do
      Exqlite.query(conn, "BEGIN TRANSACTION", [])
    end
  else
    defp begin_transaction(%Yesql.Driver.SQLite{}, _conn) do
      {:error, :driver_not_loaded}
    end
  end

  defp begin_transaction(_, _), do: {:error, :unsupported_transaction}

  if Code.ensure_loaded?(Postgrex) do
    defp commit_transaction(%Yesql.Driver.Postgrex{}, conn) do
      Postgrex.query(conn, "COMMIT", [])
    end
  else
    defp commit_transaction(%Yesql.Driver.Postgrex{}, _conn) do
      {:error, :driver_not_loaded}
    end
  end

  if Code.ensure_loaded?(MyXQL) do
    defp commit_transaction(%Yesql.Driver.MySQL{}, conn) do
      MyXQL.query(conn, "COMMIT", [])
    end
  else
    defp commit_transaction(%Yesql.Driver.MySQL{}, _conn) do
      {:error, :driver_not_loaded}
    end
  end

  if Code.ensure_loaded?(Tds) do
    defp commit_transaction(%Yesql.Driver.MSSQL{}, conn) do
      Tds.query(conn, "COMMIT", [])
    end
  else
    defp commit_transaction(%Yesql.Driver.MSSQL{}, _conn) do
      {:error, :driver_not_loaded}
    end
  end

  if Code.ensure_loaded?(Jamdb.Oracle) do
    defp commit_transaction(%Yesql.Driver.Oracle{}, conn) do
      Jamdb.Oracle.query(conn, "COMMIT", [])
    end
  else
    defp commit_transaction(%Yesql.Driver.Oracle{}, _conn) do
      {:error, :driver_not_loaded}
    end
  end

  if Code.ensure_loaded?(Exqlite) do
    defp commit_transaction(%Yesql.Driver.SQLite{}, conn) do
      Exqlite.query(conn, "COMMIT", [])
    end
  else
    defp commit_transaction(%Yesql.Driver.SQLite{}, _conn) do
      {:error, :driver_not_loaded}
    end
  end

  defp commit_transaction(_, _), do: {:error, :unsupported_transaction}

  if Code.ensure_loaded?(Postgrex) do
    defp rollback_transaction(%Yesql.Driver.Postgrex{}, conn) do
      Postgrex.query(conn, "ROLLBACK", [])
    end
  else
    defp rollback_transaction(%Yesql.Driver.Postgrex{}, _conn) do
      {:error, :driver_not_loaded}
    end
  end

  if Code.ensure_loaded?(MyXQL) do
    defp rollback_transaction(%Yesql.Driver.MySQL{}, conn) do
      MyXQL.query(conn, "ROLLBACK", [])
    end
  else
    defp rollback_transaction(%Yesql.Driver.MySQL{}, _conn) do
      {:error, :driver_not_loaded}
    end
  end

  if Code.ensure_loaded?(Tds) do
    defp rollback_transaction(%Yesql.Driver.MSSQL{}, conn) do
      Tds.query(conn, "ROLLBACK", [])
    end
  else
    defp rollback_transaction(%Yesql.Driver.MSSQL{}, _conn) do
      {:error, :driver_not_loaded}
    end
  end

  if Code.ensure_loaded?(Jamdb.Oracle) do
    defp rollback_transaction(%Yesql.Driver.Oracle{}, conn) do
      Jamdb.Oracle.query(conn, "ROLLBACK", [])
    end
  else
    defp rollback_transaction(%Yesql.Driver.Oracle{}, _conn) do
      {:error, :driver_not_loaded}
    end
  end

  if Code.ensure_loaded?(Exqlite) do
    defp rollback_transaction(%Yesql.Driver.SQLite{}, conn) do
      Exqlite.query(conn, "ROLLBACK", [])
    end
  else
    defp rollback_transaction(%Yesql.Driver.SQLite{}, _conn) do
      {:error, :driver_not_loaded}
    end
  end

  defp rollback_transaction(_, _), do: {:error, :unsupported_transaction}
end
