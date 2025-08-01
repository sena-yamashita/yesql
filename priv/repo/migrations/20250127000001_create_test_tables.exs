defmodule Yesql.TestRepo.Migrations.CreateTestTables do
  use Ecto.Migration

  def up do
    # users テーブル
    create_if_not_exists table(:users) do
      add :name, :string, null: false
      add :age, :integer, null: false
      add :email, :string
      
      timestamps()
    end

    # cats テーブル
    create_if_not_exists table(:cats, primary_key: false) do
      add :age, :integer, null: false
      add :name, :string
    end

    # products テーブル
    create_if_not_exists table(:products) do
      add :name, :string, null: false
      add :price, :decimal, precision: 10, scale: 2
      add :category, :string
      add :in_stock, :boolean, default: true
      
      timestamps()
    end

    # large_data テーブル（ストリーミングテスト用）
    create_if_not_exists table(:large_data) do
      add :value, :integer
      add :data, :text
      
      timestamps()
    end

    # batch_test テーブル（バッチ処理テスト用）
    create_if_not_exists table(:batch_test) do
      add :name, :string
      add :value, :integer
      add :created_at, :utc_datetime, default: fragment("CURRENT_TIMESTAMP")
    end

    # インデックスは別のマイグレーションで作成
  end

  def down do
    drop_if_exists index(:large_data, [:value])
    drop_if_exists index(:products, [:category])
    drop_if_exists index(:users, [:email])
    drop_if_exists index(:users, [:age])
    
    drop_if_exists table(:batch_test)
    drop_if_exists table(:large_data)
    drop_if_exists table(:products)
    drop_if_exists table(:cats)
    drop_if_exists table(:users)
  end
end