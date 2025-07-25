defmodule TestYesqlDepTest do
  use ExUnit.Case
  doctest TestYesqlDep

  test "greets the world" do
    assert TestYesqlDep.hello() == :world
  end
end
