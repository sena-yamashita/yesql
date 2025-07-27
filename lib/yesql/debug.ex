defmodule Yesql.Debug do
  @moduledoc """
  デバッグ用モジュール
  """

  def check_environment do
    IO.puts("=== YesQL Debug Information ===")
    IO.puts("Elixir Version: #{System.version()}")
    IO.puts("OTP Version: #{System.otp_release()}")
    IO.puts("YesQL Version: 2.1.0")
    IO.puts("Mix Environment: #{Mix.env()}")

    IO.puts("\n=== Available Drivers ===")
    check_driver(:postgrex, Postgrex)
    check_driver(:myxql, MyXQL)
    check_driver(:duckdbex, Duckdbex)
    check_driver(:exqlite, Exqlite)
    check_driver(:tds, Tds)
    check_driver(:jamdb_oracle, Jamdb.Oracle)
    check_driver(:ecto, Ecto)
    check_driver(:ecto_sql, Ecto.Adapters.SQL)

    IO.puts("\n=== Compilation Path ===")
    IO.inspect(Mix.Project.build_path())

    :ok
  end

  defp check_driver(name, module) do
    case Code.ensure_loaded?(module) do
      true -> IO.puts("✓ #{name}: available")
      false -> IO.puts("✗ #{name}: not available")
    end
  end
end
