# Docker環境でのテストヘルパー
# このファイルはtest/test_helper.exsから読み込まれます

# Docker環境での接続設定
if System.get_env("DOCKER_TEST") == "true" do
  # PostgreSQL設定（デフォルト）
  Application.put_env(:yesql, :postgres_config, [
    hostname: System.get_env("POSTGRES_HOST", "localhost"),
    port: String.to_integer(System.get_env("POSTGRES_PORT", "5432")),
    username: System.get_env("POSTGRES_USER", "postgres"),
    password: System.get_env("POSTGRES_PASSWORD", "postgres"),
    database: System.get_env("POSTGRES_DATABASE", "yesql_test"),
    pool: Ecto.Adapters.SQL.Sandbox
  ])

  # MySQL設定
  if System.get_env("MYSQL_TEST") == "true" do
    Application.put_env(:yesql, :mysql_config, [
      hostname: System.get_env("MYSQL_HOST", "localhost"),
      port: String.to_integer(System.get_env("MYSQL_PORT", "3306")),
      username: System.get_env("MYSQL_USER", "root"),
      password: System.get_env("MYSQL_PASSWORD", "root"),
      database: System.get_env("MYSQL_DATABASE", "yesql_test"),
      pool: Ecto.Adapters.SQL.Sandbox
    ])
  end

  # MSSQL設定
  if System.get_env("MSSQL_TEST") == "true" do
    Application.put_env(:yesql, :mssql_config, [
      hostname: System.get_env("MSSQL_HOST", "localhost"),
      port: String.to_integer(System.get_env("MSSQL_PORT", "1433")),
      username: System.get_env("MSSQL_USER", "sa"),
      password: System.get_env("MSSQL_PASSWORD", "YourStrong@Passw0rd"),
      database: System.get_env("MSSQL_DATABASE", "master"),
      pool: Ecto.Adapters.SQL.Sandbox
    ])
  end
end