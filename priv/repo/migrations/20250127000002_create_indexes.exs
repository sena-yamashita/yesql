defmodule Yesql.TestRepo.Migrations.CreateIndexes do
  use Ecto.Migration

  def up do
    # インデックスの作成はベストエフォート
    # 既に存在する場合はスキップ
    
    # PostgreSQL
    if repo().__adapter__() == Ecto.Adapters.Postgres do
      execute "CREATE INDEX IF NOT EXISTS users_age_index ON users(age)", ""
      execute "CREATE INDEX IF NOT EXISTS products_category_index ON products(category)", ""  
      execute "CREATE INDEX IF NOT EXISTS large_data_value_index ON large_data(value)", ""
    end
    
    # SQL Server
    if repo().__adapter__() == Ecto.Adapters.Tds do
      execute """
      IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'users_age_index' AND object_id = OBJECT_ID('users'))
      CREATE INDEX users_age_index ON users(age)
      """, ""
      
      execute """
      IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'products_category_index' AND object_id = OBJECT_ID('products'))
      CREATE INDEX products_category_index ON products(category)
      """, ""
      
      execute """
      IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'large_data_value_index' AND object_id = OBJECT_ID('large_data'))
      CREATE INDEX large_data_value_index ON large_data(value)
      """, ""
    end
    
    # MySQL - エラーを無視
    if repo().__adapter__() == Ecto.Adapters.MyXQL do
      # 既存のインデックスがある場合、MySQLはエラーを返すが、それは問題ない
      :ok
    end
  end

  def down do
    # インデックスの削除
    if repo().__adapter__() in [Ecto.Adapters.Postgres, Ecto.Adapters.MyXQL] do
      execute "DROP INDEX IF EXISTS users_age_index", ""
      execute "DROP INDEX IF EXISTS products_category_index", "" 
      execute "DROP INDEX IF EXISTS large_data_value_index", ""
    end
    
    # SQL Server
    if repo().__adapter__() == Ecto.Adapters.Tds do
      execute "DROP INDEX IF EXISTS users_age_index ON users", ""
      execute "DROP INDEX IF EXISTS products_category_index ON products", ""
      execute "DROP INDEX IF EXISTS large_data_value_index ON large_data", ""
    end
  end
end