# Postgrex

## 依存関係のインストール

`mix.exs`ファイルに両方の依存関係を追加します：

```elixir
  defp deps do
    [
      {:postgrex, "~> 0.15.4"},
      {:yesql, "~> 1.0"}
    ]
  end
```

## Postgrexプロセスの起動

[手動で起動](https://hexdocs.pm/postgrex/readme.html#example)することもできますが、後で簡単に参照できる名前と共にスーパーバイザーツリー内でこのプロセスを宣言することをお勧めします。

```elixir
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    conn_params = [
      name: ConnectionPool,
      hostname: "host", username: "user", password: "pass", database: "your_db"
    ]

    children = [
      {Postgrex, conn_params},
    ]

    Supervisor.start_link(children, [strategy: :one_for_one])
  end
end
```

## Yesqlでの宣言

次に、PostgrexとPostgrexプロセスを使用することを指定して、Yesqlモジュールを宣言します：

```elixir
    defmodule Query do
      use Yesql, driver: Postgrex, conn: ConnectionPool

      Yesql.defquery("some/where/now.sql")
      Yesql.defquery("some/where/select_users.sql")
      Yesql.defquery("some/where/select_users_by_country.sql")
    end

    Query.now []
    # => {:ok, [%{now: ~U[2020-05-09 21:22:54.680122Z]}]}

    Query.users_by_country(country_code: "jpn")
    # => {:ok, [%{name: "太郎", country_code: "jpn"}]}
```