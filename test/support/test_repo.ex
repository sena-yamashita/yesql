# 各データベース用のリポジトリモジュールを定義
defmodule Yesql.TestRepo.Postgres do
  use Ecto.Repo,
    otp_app: :yesql,
    adapter: Ecto.Adapters.Postgres
end

defmodule Yesql.TestRepo.MySQL do
  use Ecto.Repo,
    otp_app: :yesql,
    adapter: Ecto.Adapters.MyXQL
end

defmodule Yesql.TestRepo.MSSQL do
  use Ecto.Repo,
    otp_app: :yesql,
    adapter: Ecto.Adapters.Tds
end

# SQLiteはEctoアダプターがないため、直接ドライバーを使用

defmodule Yesql.TestRepo do
  @moduledoc """
  テスト用の統一的なEctoリポジトリインターフェース
  環境変数でデータベースアダプターを切り替え可能
  """

  def repo do
    case System.get_env("TEST_DATABASE", "postgres") do
      "postgres" -> Yesql.TestRepo.Postgres
      "mysql" -> Yesql.TestRepo.MySQL
      "mssql" -> Yesql.TestRepo.MSSQL
      _ -> Yesql.TestRepo.Postgres
    end
  end

  # 各Repoの関数をデリゲート
  def start_link(opts \\ []) do
    repo().start_link(opts)
  end

  def stop(timeout \\ 5000) do
    repo().stop(timeout)
  end

  def query(sql, params \\ [], opts \\ []) do
    repo().query(sql, params, opts)
  end

  def query!(sql, params \\ [], opts \\ []) do
    repo().query!(sql, params, opts)
  end

  def transaction(fun_or_multi, opts \\ []) do
    repo().transaction(fun_or_multi, opts)
  end

  def __adapter__ do
    repo().__adapter__()
  end
end

defmodule Yesql.TestMigration do
  @moduledoc """
  各データベース用の共通テストテーブル作成
  """
  use Ecto.Migration

  def up do
    create table(:users) do
      add :name, :string, null: false
      add :age, :integer, null: false
      add :email, :string
      timestamps()
    end

    create table(:cats) do
      add :name, :string
      add :age, :integer, null: false
    end

    create table(:products) do
      add :name, :string, null: false
      add :price, :decimal, precision: 10, scale: 2
      add :category, :string
      add :in_stock, :boolean, default: true
      timestamps()
    end

    # ストリーミングテスト用の大量データテーブル
    create table(:large_data) do
      add :value, :integer
      add :data, :text
      timestamps()
    end
  end

  def down do
    drop table(:large_data)
    drop table(:products)
    drop table(:cats)
    drop table(:users)
  end
end