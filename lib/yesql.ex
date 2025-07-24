defmodule Yesql do
  @moduledoc """

      defmodule Query do
        use Yesql, driver: Postgrex, conn: MyApp.ConnectionPool

        Yesql.defquery("some/where/select_users_by_country.sql")
      end

      Query.users_by_country(country_code: "gbr")
      # => {:ok, [%{name: "Louis", country_code: "gbr"}]}

  ## Supported drivers

  - `Postgrex`
  - `Ecto`, for which `conn` is an Ecto repo.

  ## Configuration

  Checkout the [Postgrex](postgrex_configuration.html) or
  [Ecto](ecto_configuration.html) configuration guides.

  """

  alias __MODULE__.{NoDriver, UnknownDriver, MissingParam}
  alias Yesql.{Driver, DriverFactory}

  defmacro __using__(opts) do
    quote bind_quoted: binding() do
      @yesql_private__driver opts[:driver]
      @yesql_private__conn opts[:conn]
    end
  end

  defmacro defquery(file_path, opts \\ []) do
    quote bind_quoted: binding() do
      name = file_path |> Path.basename(".sql") |> String.to_atom()
      driver_name = opts[:driver] || @yesql_private__driver || raise(NoDriver, name)
      conn = opts[:conn] || @yesql_private__conn

      # ドライバー名を正規化（モジュール名からアトムへ）
      driver_atom = case driver_name do
        Postgrex -> :postgrex
        Ecto -> :ecto
        atom when is_atom(atom) -> atom
        _ -> driver_name
      end
      
      # ドライバーインスタンスを作成
      case DriverFactory.create(driver_atom) do
        {:ok, driver_instance} ->
          # SQLファイルを読み込んでパラメータを変換
          raw_sql = file_path |> File.read!() |> String.replace("\r\n", "\n")
          {sql, param_spec} = Driver.convert_params(driver_instance, raw_sql, [])

          def unquote(name)(conn, args) do
            Yesql.exec(conn, unquote(Macro.escape(driver_instance)), unquote(sql), unquote(param_spec), args)
          end

          if conn do
            def unquote(name)(args) do
              Yesql.exec(unquote(conn), unquote(Macro.escape(driver_instance)), unquote(sql), unquote(param_spec), args)
            end
          end
          
        {:error, :unknown_driver} ->
          raise(UnknownDriver, driver_atom)
          
        {:error, :driver_not_loaded} ->
          raise(UnknownDriver, "Driver #{driver_atom} is not loaded. Make sure the required library is in your dependencies.")
      end
    end
  end

  @doc false
  def parse(sql) do
    with {:ok, tokens, _} <- Yesql.Tokenizer.tokenize(sql) do
      {_, query_iodata, params_pairs} =
        tokens
        |> Enum.reduce({1, [], []}, &extract_param/2)

      sql = IO.iodata_to_binary(query_iodata)
      params = params_pairs |> Keyword.keys() |> Enum.reverse()

      {:ok, sql, params}
    end
  end

  defp extract_param({:named_param, param}, {i, sql, params}) do
    case params[param] do
      nil ->
        {i + 1, [sql, "$#{i}"], [{param, i} | params]}

      num ->
        {i, [sql, "$#{num}"], params}
    end
  end

  defp extract_param({:fragment, fragment}, {i, sql, params}) do
    {i, [sql, fragment], params}
  end

  @doc false
  def exec(conn, driver, sql, param_spec, data) do
    param_list = Enum.map(param_spec, &fetch_param(data, &1))

    with {:ok, result} <- Driver.execute(driver, conn, sql, param_list) do
      Driver.process_result(driver, {:ok, result})
    end
  end

  defp fetch_param(data, key) do
    case dict_fetch(data, key) do
      {:ok, value} -> value
      :error -> raise(MissingParam, key)
    end
  end

  defp dict_fetch(dict, key) when is_map(dict), do: Map.fetch(dict, key)
  defp dict_fetch(dict, key) when is_list(dict), do: Keyword.fetch(dict, key)

  # parseメソッドは後方互換性のために残しておく
  # 新しいドライバーシステムでは直接使用しない
end
