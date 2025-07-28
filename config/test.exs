import Config

# 共通設定
base_config = [
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10,
  # マイグレーションパスの設定
  priv: "priv/repo"
]

# PostgreSQLの設定
config :yesql, Yesql.TestRepo.Postgres,
  username: System.get_env("POSTGRES_USER", "postgres"),
  password: System.get_env("POSTGRES_PASSWORD", "postgres"),
  hostname: System.get_env("POSTGRES_HOST", "localhost"),
  database: "yesql_test",
  port: String.to_integer(System.get_env("POSTGRES_PORT", "5432")),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10,
  priv: "priv/repo",
  migration_source: "schema_migrations",
  migration_primary_key: [type: :bigserial],
  migration_timestamps: [type: :utc_datetime]

# MySQLの設定
config :yesql, Yesql.TestRepo.MySQL,
  username: System.get_env("MYSQL_USER", "root"),
  password: System.get_env("MYSQL_PASSWORD", "root"),
  hostname: System.get_env("MYSQL_HOST", "localhost"),
  database: "yesql_test",
  port: String.to_integer(System.get_env("MYSQL_PORT", "3306")),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10,
  priv: "priv/repo"

# MSSQLの設定
config :yesql, Yesql.TestRepo.MSSQL,
  username: System.get_env("MSSQL_USER", "sa"),
  password: System.get_env("MSSQL_PASSWORD", "YourStrong@Passw0rd"),
  hostname: System.get_env("MSSQL_HOST", "localhost"),
  database: "yesql_test",
  port: String.to_integer(System.get_env("MSSQL_PORT", "1433")),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10,
  priv: "priv/repo",
  # CI環境での自己署名証明書に対応
  trust_server_certificate: true

# アプリケーション設定
# 環境変数に基づいて必要なリポジトリのみを設定
ecto_repos = 
  cond do
    System.get_env("SQLITE_TEST") == "true" -> []
    System.get_env("DUCKDB_TEST") == "true" -> []
    System.get_env("MYSQL_TEST") == "true" -> [Yesql.TestRepo.MySQL]
    System.get_env("MSSQL_TEST") == "true" -> [Yesql.TestRepo.MSSQL]
    true -> [Yesql.TestRepo.Postgres]  # デフォルト
  end

config :yesql, ecto_repos: ecto_repos

# ログレベルの設定
config :logger, level: :info
