defmodule ExseqTest do
  use ExUnit.Case
  doctest Exseq

  test "greets the world" do
    assert Exseq.hello() == :world
  end
end
