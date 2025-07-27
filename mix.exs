defmodule Yesql.Mixfile do
  use Mix.Project

  def project do
    [
      app: :yesql,
      version: "2.1.5",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: [:leex] ++ Mix.compilers(),
      deps: deps(),
      dialyzer: dialyzer(),
      name: "Yesql",
      description: "Using plain old SQL to query databases",
      source_url: "https://github.com/lpil/yesql",
      docs: docs(),
      package: [
        maintainers: ["Louis Pilfold"],
        licenses: ["Apache 2.0"],
        links: %{"GitHub" => "https://github.com/lpil/yesql"},
        files: ~w(LICENCE README.md lib src mix.exs)
      ],
      aliases: aliases()
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md",
        "CHANGELOG.md",
        "guides/ecto_configuration.md",
        "guides/postgrex_configuration.md",
        "guides/multi_driver_configuration.md",
        "guides/mysql_configuration.md",
        "guides/mssql_configuration.md",
        "guides/oracle_configuration.md",
        "guides/sqlite_configuration.md",
        "guides/migration_guide.md",
        "guides/streaming_guide.md",
        "guides/production_checklist.md"
      ],
      groups_for_extras: [
        Configuration: Path.wildcard("guides/*.md")
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  def cli do
    [
      preferred_envs: [
        "test.unit": :test,
        "test.full": :test,
        "test.ci": :test,
        "test.postgres": :test,
        "test.mysql": :test,
        "test.mssql": :test,
        "test.duckdb": :test,
        "test.watch.unit": :test
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp dialyzer do
    [
      plt_core_path: "priv/plts",
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
      flags: [
        :error_handling,
        :no_opaque,
        :unmatched_returns
      ],
      # オプショナルな依存関係は除外
      plt_add_deps: :apps_direct,
      plt_add_apps: [:postgrex, :ecto, :ecto_sql],
      # 既知の警告を無視
      ignore_warnings: "dialyzer_ignore.exs"
    ]
  end

  defp aliases do
    [
      # ローカル開発用: 単体テストのみ実行（高速）
      "test.unit": ["test --only unit"],

      # 全テスト実行（DB接続必要）
      "test.full": ["cmd FULL_TEST=true mix test"],

      # CI用フルテスト
      "test.ci": ["cmd CI=true mix test"],

      # 各DBごとのテスト
      "test.postgres": ["cmd FULL_TEST=true mix test --only postgres"],
      "test.mysql": ["cmd FULL_TEST=true MYSQL_TEST=true mix test --only mysql"],
      "test.mssql": ["cmd FULL_TEST=true MSSQL_TEST=true mix test --only mssql"],
      "test.duckdb": ["cmd DUCKDB_TEST=true mix test --only duckdb"],

      # Watch mode for unit tests
      "test.watch.unit": ["test.watch --only unit"]
    ]
  end

  defp deps do
    [
      # Postgresql driver
      {:postgrex, ">= 0.15.0", optional: true},
      # Database abstraction
      {:ecto_sql, ">= 3.4.0", optional: true},
      {:ecto, ">= 3.4.0", optional: true},
      # DuckDB driver
      {:duckdbex, "~> 0.3.9", optional: true},
      # MySQL/MariaDB driver
      {:myxql, "~> 0.6", optional: true},
      # MSSQL driver
      {:tds, "~> 2.3", optional: true},
      # Oracle driver
      {:jamdb_oracle, "~> 0.5", optional: true},
      # SQLite driver
      {:exqlite, "~> 0.13", optional: true},

      # JSON encoder/decoder (required by Postgrex for jsonb types)
      {:jason, "~> 1.0", optional: true},

      # Parser generator
      {:nimble_parsec, "~> 1.4", runtime: false},

      # Development dependencies
      # Automatic testing tool
      {:mix_test_watch, ">= 0.0.0", only: :dev},
      # Documentation generator
      {:ex_doc, "~> 0.23", only: :dev},
      # Static analysis tool
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      # Benchmarking
      {:benchee, "~> 1.0", only: :bench, runtime: false}
    ]
  end
end
