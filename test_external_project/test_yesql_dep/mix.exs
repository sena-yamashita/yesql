defmodule TestYesqlDep.MixProject do
  use Mix.Project

  def project do
    [
      app: :test_yesql_dep,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:yesql, git: "https://github.com/sena-yamashita/yesql.git", branch: "master"}
    ]
  end
end
