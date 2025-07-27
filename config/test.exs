import Config

# データベースタイプを環境変数から取得
db_type = System.get_env("TEST_DATABASE", "postgres")

# 共通設定
base_config = [
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10
]

# データベース固有の設定
db_config = case db_type do
  "postgres" ->
    [
      username: System.get_env("POSTGRES_USER", "postgres"),
      password: System.get_env("POSTGRES_PASSWORD", "postgres"),
      hostname: System.get_env("POSTGRES_HOST", "localhost"),
      database: "yesql_test",
      port: String.to_integer(System.get_env("POSTGRES_PORT", "5432"))
    ]

  "mysql" ->
    [
      username: System.get_env("MYSQL_USER", "root"),
      password: System.get_env("MYSQL_PASSWORD", "root"),
      hostname: System.get_env("MYSQL_HOST", "localhost"),
      database: "yesql_test",
      port: String.to_integer(System.get_env("MYSQL_PORT", "3306"))
    ]

  "mssql" ->
    [
      username: System.get_env("MSSQL_USER", "sa"),
      password: System.get_env("MSSQL_PASSWORD", "YourStrong@Passw0rd"),
      hostname: System.get_env("MSSQL_HOST", "localhost"),
      database: "yesql_test",
      port: String.to_integer(System.get_env("MSSQL_PORT", "1433"))
    ]

  "sqlite" ->
    [
      database: Path.expand("../yesql_test.db", Path.dirname(__ENV__.file))
    ]

  _ ->
    raise "Unknown database type: #{db_type}"
end

# 各Repoの設定
config :yesql, Yesql.TestRepo.Postgres,
  Keyword.merge(base_config, db_config)

config :yesql, Yesql.TestRepo.MySQL,
  Keyword.merge(base_config, db_config)

config :yesql, Yesql.TestRepo.MSSQL,
  Keyword.merge(base_config, db_config)

# アプリケーション設定
config :yesql,
  ecto_repos: [Yesql.TestRepo.Postgres, Yesql.TestRepo.MySQL, Yesql.TestRepo.MSSQL]

# ログレベルの設定
config :logger, level: :info