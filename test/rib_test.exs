defmodule RibTest do
  use ExUnit.Case
  doctest Rib

  test "greets the world" do
    assert Rib.hello() == :world
  end
end
