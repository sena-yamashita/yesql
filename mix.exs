defmodule Yesql.Mixfile do
  use Mix.Project

  def project do
    [
      app: :yesql,
      version: "2.1.3",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: [:leex] ++ Mix.compilers(),
      deps: deps(),
      name: "Yesql",
      description: "Using plain old SQL to query databases",
      source_url: "https://github.com/lpil/yesql",
      docs: docs(),
      package: [
        maintainers: ["Louis Pilfold"],
        licenses: ["Apache 2.0"],
        links: %{"GitHub" => "https://github.com/lpil/yesql"},
        files: ~w(LICENCE README.md lib src mix.exs)
      ]
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

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

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

      # Automatic testing tool
      {:mix_test_watch, ">= 0.0.0", only: :dev},
      # Documentation generator
      {:ex_doc, "~> 0.23", only: :dev},
      # Benchmarking
      {:benchee, "~> 1.0", only: :bench, runtime: false}
    ]
  end
end
