defmodule Yesql.DriverFactory do
  @moduledoc """
  ドライバーインスタンスを作成するファクトリーモジュール
  """
  
  @doc """
  ドライバー名からドライバーインスタンスを作成します。
  
  ## パラメータ
  - `driver_name` - ドライバー名のアトム (:postgrex, :ecto, :duckdb など)
  
  ## 戻り値
  - `{:ok, driver}` - 成功時
  - `{:error, :unknown_driver}` - 不明なドライバー名の場合
  - `{:error, :driver_not_loaded}` - ドライバーが読み込まれていない場合
  """
  def create(driver_name) do
    case driver_name do
      :postgrex ->
        if match?({:module, _}, Code.ensure_compiled(Postgrex)) do
          {:ok, %Yesql.Driver.Postgrex{}}
        else
          {:error, :driver_not_loaded}
        end
        
      :ecto ->
        if match?({:module, _}, Code.ensure_compiled(Ecto)) do
          {:ok, %Yesql.Driver.Ecto{}}
        else
          {:error, :driver_not_loaded}
        end
        
      :duckdb ->
        if match?({:module, _}, Code.ensure_compiled(Duckdbex)) do
          {:ok, %Yesql.Driver.DuckDB{}}
        else
          {:error, :driver_not_loaded}
        end
        
      _ ->
        {:error, :unknown_driver}
    end
  end
  
  @doc """
  利用可能なドライバーのリストを返します。
  """
  def available_drivers do
    drivers = []
    
    drivers = if match?({:module, _}, Code.ensure_compiled(Postgrex)), do: [:postgrex | drivers], else: drivers
    drivers = if match?({:module, _}, Code.ensure_compiled(Ecto)), do: [:ecto | drivers], else: drivers
    drivers = if match?({:module, _}, Code.ensure_compiled(Duckdbex)), do: [:duckdb | drivers], else: drivers
    
    drivers
  end
end