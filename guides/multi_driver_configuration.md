# Multi-Driver Configuration

Yesql now supports multiple database drivers through a flexible driver abstraction layer. This guide explains how to configure and use different drivers in your application.

## Available Drivers

- **Postgrex** - PostgreSQL database driver
- **Ecto** - Works with any Ecto repository
- **DuckDB** - Analytical database for OLAP workloads

## Configuration Options

### Module-level Configuration

Configure the driver at the module level using the `use` macro:

```elixir
defmodule MyApp.Queries do
  use Yesql, driver: :postgrex, conn: MyApp.ConnectionPool
  
  Yesql.defquery("queries/users.sql")
end
```

### Per-Query Configuration

Override the driver for specific queries:

```elixir
defmodule MyApp.Queries do
  use Yesql
  
  # Uses PostgreSQL
  Yesql.defquery("queries/users.sql", driver: :postgrex)
  
  # Uses DuckDB for analytics
  Yesql.defquery("queries/analytics.sql", driver: :duckdb)
end
```

## Driver-Specific Setup

### PostgreSQL with Postgrex

```elixir
# In your application startup
{:ok, pid} = Postgrex.start_link(
  hostname: "localhost",
  database: "myapp_dev",
  username: "postgres",
  password: "postgres",
  pool_size: 10
)

# In your query module
defmodule MyApp.PostgresQueries do
  use Yesql, driver: :postgrex, conn: pid
  
  Yesql.defquery("queries/users.sql")
end
```

### Ecto Repository

```elixir
defmodule MyApp.Queries do
  use Yesql, driver: :ecto, conn: MyApp.Repo
  
  Yesql.defquery("queries/users.sql")
end

# Usage
MyApp.Queries.users_by_country(country: "USA")
```

### DuckDB

```elixir
# Setup DuckDB connection
{:ok, db} = Duckdbex.open("analytics.duckdb")
{:ok, conn} = Duckdbex.connection(db)

defmodule MyApp.Analytics do
  use Yesql, driver: :duckdb
  
  Yesql.defquery("queries/revenue_report.sql")
end

# Usage
MyApp.Analytics.revenue_report(conn, year: 2024)
```

## Parameter Formats

Different databases use different parameter formats, but Yesql handles the conversion automatically:

### SQL File (uses named parameters)
```sql
-- queries/find_user.sql
SELECT * FROM users
WHERE email = :email
  AND active = :active
```

### Generated SQL by Driver
- **PostgreSQL/DuckDB**: `SELECT * FROM users WHERE email = $1 AND active = $2`
- **MySQL** (future): `SELECT * FROM users WHERE email = ? AND active = ?`

## Dependencies

Add the required driver dependencies to your `mix.exs`:

```elixir
defp deps do
  [
    # For PostgreSQL
    {:postgrex, "~> 0.15", optional: true},
    
    # For Ecto
    {:ecto, "~> 3.4", optional: true},
    {:ecto_sql, "~> 3.4", optional: true},
    
    # For DuckDB
    {:duckdbex, "~> 0.3.9", optional: true},
    
    # Yesql itself
    {:yesql, "~> 1.0"}
  ]
end
```

## Checking Available Drivers

You can check which drivers are available at runtime:

```elixir
iex> Yesql.DriverFactory.available_drivers()
[:postgrex, :ecto, :duckdb]
```

## Error Handling

If you try to use a driver that isn't loaded:

```elixir
# If DuckDBex is not in your dependencies
defmodule MyApp.Queries do
  use Yesql, driver: :duckdb  # Will raise an error
end
```

Error message: `Driver duckdb is not loaded. Make sure the required library is in your dependencies.`

## Future Drivers

The driver system is designed to be extensible. Future versions may include:

- MySQL via MyXQL
- Microsoft SQL Server via TDS
- Oracle Database
- SQLite

To implement a custom driver, create a module that implements the `Yesql.Driver` protocol.