defmodule Yesql.Driver.SQLite do
  @moduledoc """
  SQLiteドライバーの実装
  
  Exqliteライブラリを使用してSQLiteデータベースへのアクセスを提供します。
  メモリデータベースとファイルベースのデータベースの両方をサポートします。
  """
  
  defstruct []
  
  # Exqliteが利用可能な場合のみプロトコル実装を定義
  if match?({:module, _}, Code.ensure_compiled(Exqlite)) do
    defimpl Yesql.Driver, for: __MODULE__ do
      @doc """
      SQLiteでクエリを実行する
      """
      def execute(_driver, conn, sql, params) do
        if Code.ensure_loaded?(Exqlite) do
          case Exqlite.query(conn, sql, params) do
            {:ok, result} ->
              process_result(_driver, {:ok, result})
            {:error, _} = error ->
              error
          end
        else
          {:error, "Exqlite is not available. Please add :exqlite to your dependencies."}
        end
      end
      
      @doc """
      名前付きパラメータをSQLiteの?形式に変換する
      """
      def convert_params(_driver, sql, _param_spec) do
        # パラメータパターンの検出
        param_regex = ~r/:([a-zA-Z_][a-zA-Z0-9_]*)/
        
        # SQLからパラメータを抽出（出現順序を保持）
        param_occurrences = Regex.scan(param_regex, sql)
        |> Enum.map(fn [full_match, param_name] -> 
          {full_match, String.to_atom(param_name)}
        end)
        
        # パラメータ名のリスト（重複を除去しない、出現順序を保持）
        param_list = Enum.map(param_occurrences, &elem(&1, 1))
        
        # ユニークなパラメータ名のリスト（出現順序を保持）
        unique_params = param_occurrences
        |> Enum.map(&elem(&1, 1))
        |> Enum.uniq()
        
        # SQLの変換（名前付きパラメータを?に置換）
        converted_sql = Regex.replace(param_regex, sql, "?")
        
        # SQLiteは?形式を使用し、パラメータは出現順序で提供される必要がある
        {converted_sql, param_list}
      end
      
      @doc """
      SQLiteの結果をマップのリストに変換する
      """
      def process_result(_driver, {:ok, result}) do
        columns = result.columns
        |> Enum.map(&String.to_atom/1)
        
        rows = result.rows
        |> Enum.map(fn row ->
          columns
          |> Enum.zip(row)
          |> Enum.into(%{})
        end)
        
        {:ok, rows}
      end
      
      def process_result(_driver, {:error, _} = error), do: error
    end
  end
  
  @doc """
  SQLiteデータベースへの接続を開く
  
  ## オプション
  
    * `:database` - データベースファイルのパス、または`:memory`でメモリDB
    * `:timeout` - クエリタイムアウト（ミリ秒）
    * `:busy_timeout` - ビジータイムアウト（ミリ秒）
    * `:cache_size` - キャッシュサイズ（ページ数）
    * `:mode` - 接続モード（:readwrite, :readonly）
  
  ## 例
  
      # ファイルベースのデータベース
      {:ok, conn} = SQLite.open("myapp.db")
      
      # メモリデータベース
      {:ok, conn} = SQLite.open(":memory:")
      
      # 読み取り専用モード
      {:ok, conn} = SQLite.open("myapp.db", mode: :readonly)
  """
  def open(database \\ ":memory:", opts \\ []) do
    unless Code.ensure_loaded?(Exqlite) do
      {:error, "Exqlite is not available. Please add :exqlite to your dependencies."}
    else
      config = [
        database: database,
        timeout: opts[:timeout] || 5000,
        busy_timeout: opts[:busy_timeout] || 2000
      ]
      
      case Exqlite.Sqlite3.open(database) do
        {:ok, db} ->
          conn = %{db: db, config: config}
          
          # 基本的な設定
          if cache_size = opts[:cache_size] do
            Exqlite.query!(conn, "PRAGMA cache_size = #{cache_size}")
          end
          
          # WALモードを有効化（ファイルベースの場合）
          if database != ":memory:" && opts[:mode] != :readonly do
            Exqlite.query!(conn, "PRAGMA journal_mode = WAL")
          end
          
          {:ok, conn}
          
        error ->
          error
      end
    end
  end
  
  @doc """
  SQLiteのバージョン情報を取得
  """
  def version(conn) do
    unless Code.ensure_loaded?(Exqlite) do
      {:error, "Exqlite is not available. Please add :exqlite to your dependencies."}
    else
      case Exqlite.query(conn, "SELECT sqlite_version()") do
        {:ok, result} ->
          [[version]] = result.rows
          {:ok, version}
        error ->
          error
      end
    end
  end
end