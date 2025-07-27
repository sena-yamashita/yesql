# テスト用のシードデータ

alias Yesql.TestRepo

# 基本的なusersデータ
users = [
  %{name: "Alice", age: 30, email: "alice@example.com", inserted_at: DateTime.utc_now(), updated_at: DateTime.utc_now()},
  %{name: "Bob", age: 25, email: "bob@example.com", inserted_at: DateTime.utc_now(), updated_at: DateTime.utc_now()},
  %{name: "Charlie", age: 35, email: "charlie@example.com", inserted_at: DateTime.utc_now(), updated_at: DateTime.utc_now()}
]

repo = TestRepo.repo()
Enum.each(users, fn user ->
  repo.insert_all("users", [user])
end)

# catsデータ
cats = [
  %{name: "Fluffy", age: 3},
  %{name: "Mittens", age: 5}
]

Enum.each(cats, fn cat ->
  repo.insert_all("cats", [cat])
end)

# productsデータ
products = [
  %{name: "Laptop", price: Decimal.new("999.99"), category: "Electronics", in_stock: true, inserted_at: DateTime.utc_now(), updated_at: DateTime.utc_now()},
  %{name: "Mouse", price: Decimal.new("29.99"), category: "Electronics", in_stock: true, inserted_at: DateTime.utc_now(), updated_at: DateTime.utc_now()},
  %{name: "Desk", price: Decimal.new("199.99"), category: "Furniture", in_stock: false, inserted_at: DateTime.utc_now(), updated_at: DateTime.utc_now()}
]

Enum.each(products, fn product ->
  repo.insert_all("products", [product])
end)

IO.puts("Seed data inserted successfully!")