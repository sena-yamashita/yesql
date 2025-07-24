defprotocol Yesql.Driver do
  @moduledoc """
  ドライバープロトコル - 各データベースドライバーが実装すべきインターフェース
  
  このプロトコルを実装することで、新しいデータベースドライバーをYesqlに追加できます。
  """

  @doc """
  SQLクエリを実行します。
  
  ## パラメータ
  - `driver` - ドライバーモジュール
  - `conn` - データベース接続
  - `sql` - 実行するSQL文（パラメータは既に変換済み）
  - `params` - パラメータリスト
  
  ## 戻り値
  - `{:ok, result}` - 成功時、resultはドライバー固有の結果形式
  - `{:error, reason}` - エラー時
  """
  @spec execute(t, any, String.t, list) :: {:ok, any} | {:error, any}
  def execute(driver, conn, sql, params)

  @doc """
  名前付きパラメータをドライバー固有の形式に変換します。
  
  ## パラメータ
  - `driver` - ドライバーモジュール
  - `sql` - 元のSQL文（名前付きパラメータ含む）
  - `param_spec` - パラメータ名のリスト
  
  ## 戻り値
  - `{converted_sql, param_mapping}` - 変換後のSQLとパラメータマッピング
  
  ## 例
  PostgreSQL: `:id, :name` → `$1, $2`
  MySQL: `:id, :name` → `?, ?`
  """
  @spec convert_params(t, String.t, list) :: {String.t, list}
  def convert_params(driver, sql, param_spec)

  @doc """
  データベースの結果を統一された形式に変換します。
  
  ## パラメータ
  - `driver` - ドライバーモジュール  
  - `raw_result` - ドライバー固有の結果形式
  
  ## 戻り値
  - `{:ok, list(map)}` - 成功時、各行をマップとして含むリスト
  - `{:error, reason}` - エラー時
  """
  @spec process_result(t, any) :: {:ok, list(map)} | {:error, any}
  def process_result(driver, raw_result)
end