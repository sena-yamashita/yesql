defmodule Yesql.Transaction do
  @moduledoc """
  トランザクション管理の改善モジュール
  
  各データベースドライバーに対して統一的なトランザクション管理インターフェースを提供します。
  """
  
  alias Yesql.{Driver, DriverFactory}
  
  @doc """
  トランザクション内でコードブロックを実行する
  
  ## パラメータ
  
    * `conn` - データベース接続
    * `fun` - トランザクション内で実行する関数
    * `opts` - オプション
      * `:driver` - 使用するドライバー（必須）
      * `:timeout` - タイムアウト（ミリ秒）
      * `:isolation_level` - 分離レベル
  
  ## 分離レベル
  
    * `:read_uncommitted` - 読み取り未コミット
    * `:read_committed` - 読み取りコミット済み（デフォルト）
    * `:repeatable_read` - 繰り返し読み取り
    * `:serializable` - シリアライズ可能
  
  ## 例
  
      {:ok, result} = Yesql.Transaction.transaction(conn, fn conn ->
        {:ok, _} = MyApp.Queries.insert_user(conn, name: "Alice")
        {:ok, _} = MyApp.Queries.update_balance(conn, user_id: 1, amount: 100)
        :ok
      end, driver: :postgrex)
  """
  def transaction(conn, fun, opts) when is_function(fun, 1) do
    driver_name = Keyword.fetch!(opts, :driver)
    isolation_level = Keyword.get(opts, :isolation_level, :read_committed)
    
    with {:ok, driver} <- DriverFactory.create(driver_name) do
      do_transaction(driver, conn, fun, isolation_level)
    end
  end
  
  @doc """
  現在のトランザクションをロールバックする
  
  トランザクション関数内で使用して、明示的にロールバックを実行します。
  
  ## 例
  
      Yesql.Transaction.transaction(conn, fn conn ->
        {:ok, _} = MyApp.Queries.insert_user(conn, name: "Alice")
        
        if some_condition do
          Yesql.Transaction.rollback(:invalid_data)
        end
        
        :ok
      end, driver: :postgrex)
  """
  def rollback(reason) do
    throw({:rollback, reason})
  end
  
  @doc """
  セーブポイントを作成する
  
  トランザクション内でセーブポイントを作成し、部分的なロールバックを可能にします。
  
  ## 例
  
      Yesql.Transaction.transaction(conn, fn conn ->
        {:ok, _} = MyApp.Queries.insert_user(conn, name: "Alice")
        
        Yesql.Transaction.savepoint(conn, "sp1", driver: :postgrex)
        
        case MyApp.Queries.risky_operation(conn) do
          {:error, _} ->
            Yesql.Transaction.rollback_to_savepoint(conn, "sp1", driver: :postgrex)
            {:ok, :partial_success}
          {:ok, _} ->
            {:ok, :full_success}
        end
      end, driver: :postgrex)
  """
  def savepoint(conn, name, opts) do
    driver_name = Keyword.fetch!(opts, :driver)
    
    with {:ok, driver} <- DriverFactory.create(driver_name) do
      create_savepoint(driver, conn, name)
    end
  end
  
  @doc """
  セーブポイントまでロールバックする
  """
  def rollback_to_savepoint(conn, name, opts) do
    driver_name = Keyword.fetch!(opts, :driver)
    
    with {:ok, driver} <- DriverFactory.create(driver_name) do
      rollback_to_savepoint(driver, conn, name)
    end
  end
  
  @doc """
  セーブポイントを解放する
  """
  def release_savepoint(conn, name, opts) do
    driver_name = Keyword.fetch!(opts, :driver)
    
    with {:ok, driver} <- DriverFactory.create(driver_name) do
      release_savepoint(driver, conn, name)
    end
  end
  
  @doc """
  トランザクションの状態を確認する
  
  現在トランザクション内にいるかどうかを確認します。
  """
  def in_transaction?(conn, opts) do
    driver_name = Keyword.fetch!(opts, :driver)
    
    with {:ok, driver} <- DriverFactory.create(driver_name) do
      check_transaction_status(driver, conn)
    end
  end
  
  # プライベート関数
  
  defp do_transaction(driver, conn, fun, isolation_level) do
    case begin_transaction_with_level(driver, conn, isolation_level) do
      {:ok, _} ->
        try do
          result = fun.(conn)
          
          case commit_transaction(driver, conn) do
            {:ok, _} -> {:ok, result}
            error ->
              # コミット失敗時は自動的にロールバックされる
              error
          end
        catch
          :throw, {:rollback, reason} ->
            rollback_transaction(driver, conn)
            {:error, {:rollback, reason}}
            
          kind, reason ->
            rollback_transaction(driver, conn)
            :erlang.raise(kind, reason, __STACKTRACE__)
        end
        
      error ->
        error
    end
  end
  
  # トランザクション開始（分離レベル付き）
  
  if Code.ensure_loaded?(Postgrex) do
    defp begin_transaction_with_level(%Yesql.Driver.Postgrex{}, conn, level) do
      isolation_sql = case level do
        :read_uncommitted -> "READ UNCOMMITTED"
        :read_committed -> "READ COMMITTED"
        :repeatable_read -> "REPEATABLE READ"
        :serializable -> "SERIALIZABLE"
      end
      
      Postgrex.query(conn, "BEGIN ISOLATION LEVEL #{isolation_sql}", [])
    end
  else
    defp begin_transaction_with_level(%Yesql.Driver.Postgrex{}, _conn, _level) do
      {:error, :driver_not_loaded}
    end
  end
  
  if Code.ensure_loaded?(MyXQL) do
    defp begin_transaction_with_level(%Yesql.Driver.MySQL{}, conn, level) do
      # MySQLは分離レベルを事前に設定
      isolation_sql = case level do
        :read_uncommitted -> "READ UNCOMMITTED"
        :read_committed -> "READ COMMITTED"
        :repeatable_read -> "REPEATABLE READ"
        :serializable -> "SERIALIZABLE"
      end
      
      with {:ok, _} <- MyXQL.query(conn, "SET TRANSACTION ISOLATION LEVEL #{isolation_sql}", []),
           {:ok, _} <- MyXQL.query(conn, "START TRANSACTION", []) do
        {:ok, :started}
      end
    end
  else
    defp begin_transaction_with_level(%Yesql.Driver.MySQL{}, _conn, _level) do
      {:error, :driver_not_loaded}
    end
  end
  
  if Code.ensure_loaded?(Tds) do
    defp begin_transaction_with_level(%Yesql.Driver.MSSQL{}, conn, level) do
      isolation_sql = case level do
        :read_uncommitted -> "READ UNCOMMITTED"
        :read_committed -> "READ COMMITTED"
        :repeatable_read -> "REPEATABLE READ"
        :serializable -> "SERIALIZABLE"
        :snapshot -> "SNAPSHOT"  # MSSQL固有
      end
      
      Tds.query(conn, "SET TRANSACTION ISOLATION LEVEL #{isolation_sql}; BEGIN TRANSACTION", [])
    end
  else
    defp begin_transaction_with_level(%Yesql.Driver.MSSQL{}, _conn, _level) do
      {:error, :driver_not_loaded}
    end
  end
  
  if Code.ensure_loaded?(Jamdb.Oracle) do
    defp begin_transaction_with_level(%Yesql.Driver.Oracle{}, conn, level) do
      # Oracleは分離レベルをセッションレベルで設定
      case level do
        :read_committed ->
          {:ok, :auto}  # デフォルト
        :serializable ->
          Jamdb.Oracle.query(conn, "SET TRANSACTION ISOLATION LEVEL SERIALIZABLE", [])
        _ ->
          {:error, :unsupported_isolation_level}
      end
    end
  else
    defp begin_transaction_with_level(%Yesql.Driver.Oracle{}, _conn, _level) do
      {:error, :driver_not_loaded}
    end
  end
  
  if Code.ensure_loaded?(Exqlite) do
    defp begin_transaction_with_level(%Yesql.Driver.SQLite{}, conn, _level) do
      # SQLiteは分離レベルの動的変更をサポートしない
      Exqlite.query(conn, "BEGIN", [])
    end
  else
    defp begin_transaction_with_level(%Yesql.Driver.SQLite{}, _conn, _level) do
      {:error, :driver_not_loaded}
    end
  end
  
  defp begin_transaction_with_level(_, _, _), do: {:error, :unsupported_driver}
  
  # コミット
  
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
      Tds.query(conn, "COMMIT TRANSACTION", [])
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
  
  # ロールバック
  
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
      Tds.query(conn, "ROLLBACK TRANSACTION", [])
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
  
  # セーブポイント
  
  if Code.ensure_loaded?(Postgrex) do
    defp create_savepoint(%Yesql.Driver.Postgrex{}, conn, name) do
      Postgrex.query(conn, "SAVEPOINT #{name}", [])
    end
  else
    defp create_savepoint(%Yesql.Driver.Postgrex{}, _conn, _name) do
      {:error, :driver_not_loaded}
    end
  end
  
  if Code.ensure_loaded?(MyXQL) do
    defp create_savepoint(%Yesql.Driver.MySQL{}, conn, name) do
      MyXQL.query(conn, "SAVEPOINT #{name}", [])
    end
  else
    defp create_savepoint(%Yesql.Driver.MySQL{}, _conn, _name) do
      {:error, :driver_not_loaded}
    end
  end
  
  if Code.ensure_loaded?(Tds) do
    defp create_savepoint(%Yesql.Driver.MSSQL{}, conn, name) do
      Tds.query(conn, "SAVE TRANSACTION #{name}", [])
    end
  else
    defp create_savepoint(%Yesql.Driver.MSSQL{}, _conn, _name) do
      {:error, :driver_not_loaded}
    end
  end
  
  if Code.ensure_loaded?(Jamdb.Oracle) do
    defp create_savepoint(%Yesql.Driver.Oracle{}, conn, name) do
      Jamdb.Oracle.query(conn, "SAVEPOINT #{name}", [])
    end
  else
    defp create_savepoint(%Yesql.Driver.Oracle{}, _conn, _name) do
      {:error, :driver_not_loaded}
    end
  end
  
  if Code.ensure_loaded?(Exqlite) do
    defp create_savepoint(%Yesql.Driver.SQLite{}, conn, name) do
      Exqlite.query(conn, "SAVEPOINT #{name}", [])
    end
  else
    defp create_savepoint(%Yesql.Driver.SQLite{}, _conn, _name) do
      {:error, :driver_not_loaded}
    end
  end
  
  
  # トランザクション状態確認
  
  if Code.ensure_loaded?(Postgrex) do
    defp check_transaction_status(%Yesql.Driver.Postgrex{}, conn) do
      case Postgrex.query(conn, "SELECT current_setting('transaction_isolation')", []) do
        {:ok, _} -> {:ok, true}
        _ -> {:ok, false}
      end
    end
  else
    defp check_transaction_status(%Yesql.Driver.Postgrex{}, _conn) do
      {:error, :driver_not_loaded}
    end
  end
  
  if Code.ensure_loaded?(MyXQL) do
    defp check_transaction_status(%Yesql.Driver.MySQL{}, conn) do
      case MyXQL.query(conn, "SELECT @@in_transaction", []) do
        {:ok, %{rows: [[1]]}} -> {:ok, true}
        _ -> {:ok, false}
      end
    end
  else
    defp check_transaction_status(%Yesql.Driver.MySQL{}, _conn) do
      {:error, :driver_not_loaded}
    end
  end
  
  defp check_transaction_status(_, _) do
    {:error, :not_implemented}
  end
end