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
      def execute(driver, conn, sql, params) do
        if Code.ensure_loaded?(Exqlite) do
          case Exqlite.query(conn, sql, params) do
            {:ok, result} ->
              process_result(driver, {:ok, result})

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
        # 設定されたトークナイザーを使用してSQLトークンを解析
        with {:ok, tokens, _} <- Yesql.TokenizerHelper.tokenize(sql) do
          # SQLiteの?形式に変換（重複を許可）
          format_fn = fn -> "?" end
          Yesql.TokenizerHelper.extract_params_with_duplicates(tokens, format_fn)
        end
      end

      @doc """
      SQLiteの結果をマップのリストに変換する
      """
      def process_result(_driver, {:ok, result}) when is_list(result) do
        # 既にマップのリストとして処理されている場合
        {:ok, result}
      end

      def process_result(_driver, {:ok, result}) when is_map(result) do
        # Exqlite.Result形式の場合
        columns =
          result.columns
          |> Enum.map(&String.to_atom/1)

        rows =
          result.rows
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
            # SQLiteの直接操作は、別途Exqlite経由で行う必要がある
            # TODO: 適切なExqlite接続を使用してPRAGMAを設定
            _ = cache_size
          end

          # WALモードを有効化（ファイルベースの場合）
          if database != ":memory:" && opts[:mode] != :readonly do
            # TODO: 適切なExqlite接続を使用してPRAGMAを設定
            :ok
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
