# Ecto

## 依存関係のインストール

`postgrex`と`ecto_sql`の依存関係のみ必要ですが、`ecto`も追加しても問題ありません：

```elixir
defp deps do
  [
    {:postgrex, "~> 0.15.4"},
    {:ecto_sql, "~> 3.4"},
    {:ecto, "~> 3.4"},
    {:yesql, "~> 1.0"}
  ]
end
```

## Ectoプロセスの起動

Ectoのドキュメントには、プロジェクトにEctoを追加するための優れた[設定ガイド](https://hexdocs.pm/ecto/Ecto.html#module-repositories)があります。

まず、Repoモジュールを宣言します：

```elixir
defmodule Repo do
  use Ecto.Repo,
    otp_app: :my_app,
    adapter: Ecto.Adapters.Postgres
end
```

そして、それをスーパーバイザーツリーに追加します：

```elixir
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    conn_params = [
      name: MyApp.Repo,
      hostname: "host", username: "user", password: "pass", database: "your_db"
    ]

    children = [
      {Repo, conn_params},
    ]

    Supervisor.start_link(children, [strategy: :one_for_one])
  end
end
```

## Yesqlでの宣言

次に、EctoとEctoプロセスを使用することを指定して、Yesqlモジュールを宣言します：

```elixir
defmodule Query do
  use Yesql, driver: Ecto, conn: MyApp.Repo

  Yesql.defquery("some/where/now.sql")
  Yesql.defquery("some/where/select_users.sql")
  Yesql.defquery("some/where/select_users_by_country.sql")
end

Query.now []
# => {:ok, [%{now: ~U[2020-05-09 21:22:54.680122Z]}]}

Query.users_by_country(country_code: "jpn")
# => {:ok, [%{name: "太郎", country_code: "jpn"}]}
```