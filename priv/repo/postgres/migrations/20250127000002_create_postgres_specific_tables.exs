defmodule Yesql.TestRepo.Postgres.Migrations.CreatePostgresSpecificTables do
  use Ecto.Migration

  def up do
    # PostgreSQL固有のテーブル
    
    # JSONB型のテーブル
    create table(:test_jsonb) do
      add :data, :jsonb, null: false
    end
    
    # 配列型のテーブル
    create table(:test_arrays) do
      add :tags, {:array, :string}
      add :numbers, {:array, :integer}
    end
    
    # UUID型のテーブル
    create table(:test_uuid, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :name, :string
    end
    
    # タイムスタンプのテーブル
    create table(:test_timestamps) do
      add :event_time, :utc_datetime_usec, null: false
      add :event_name, :string
    end
    
    # 範囲型のテーブル
    execute """
    CREATE TABLE test_ranges (
      id SERIAL PRIMARY KEY,
      price_range INT4RANGE,
      valid_dates DATERANGE
    )
    """
    
    # 全文検索のテーブル
    create table(:test_fulltext) do
      add :title, :string
      add :content, :text
      add :search_vector, :tsvector
    end
    
    # 階層データのテーブル
    create table(:test_hierarchy) do
      add :name, :string
      add :parent_id, references(:test_hierarchy)
    end
    
    # 売上データのテーブル
    create table(:test_sales) do
      add :product, :string
      add :amount, :decimal
      add :sale_date, :date
    end
    
    # アイソレーションテスト用
    create table(:test_isolation) do
      add :value, :integer
    end
    
    # 部分インデックステスト用
    create table(:test_partial_index) do
      add :status, :string
      add :value, :integer
    end
    
    # 集約テスト用
    create table(:test_aggregates) do
      add :category, :string
      add :value, :integer
    end
    
    # ENUM型の作成
    execute "CREATE TYPE status_enum AS ENUM ('pending', 'in_progress', 'completed', 'cancelled')"
    execute "CREATE TYPE priority_enum AS ENUM ('low', 'medium', 'high', 'urgent')"
    
    # ENUM型を使用するテーブル
    create table(:test_enum) do
      add :status, :status_enum
      add :priority, :priority_enum
    end
    
    # インデックスの作成
    create index(:test_jsonb, [:data], using: :gin)
    create index(:test_fulltext, [:search_vector], using: :gin)
    
    # 部分インデックス
    execute "CREATE INDEX idx_test_partial ON test_partial_index (value) WHERE status = 'active'"
  end

  def down do
    # ENUM型を使用するテーブルを先に削除
    drop table(:test_enum)
    
    # ENUM型の削除
    execute "DROP TYPE IF EXISTS status_enum"
    execute "DROP TYPE IF EXISTS priority_enum"
    
    # その他のテーブルを削除
    drop table(:test_aggregates)
    drop table(:test_partial_index)
    drop table(:test_isolation)
    drop table(:test_sales)
    drop table(:test_hierarchy)
    drop table(:test_fulltext)
    execute "DROP TABLE IF EXISTS test_ranges"
    drop table(:test_timestamps)
    drop table(:test_uuid)
    drop table(:test_arrays)
    drop table(:test_jsonb)
  end
end