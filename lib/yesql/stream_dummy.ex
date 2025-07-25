defmodule Yesql.StreamDummy do
  @moduledoc """
  依存関係が利用できない場合のダミー実装
  """
  
  def query(_conn, _sql, _params, _opts) do
    {:error, :streaming_not_available}
  end
  
  def process(_conn, _sql, _params, _processor, _opts) do
    {:error, :streaming_not_available}
  end
  
  def reduce(_conn, _sql, _params, _acc, _reducer, _opts) do
    {:error, :streaming_not_available}
  end
  
  def batch_process(_conn, _sql, _params, _batch_size, _batch_fn, _opts) do
    {:error, :streaming_not_available}
  end
end