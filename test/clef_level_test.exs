defmodule ExSeq.CLEFLevelTest do
  use ExUnit.Case, async: true

  alias ExSeq.CLEFLevel

  test "maps Elixir levels to CLEF levels" do
    assert CLEFLevel.elixir_to_clef_level(:debug) == :Debug
    assert CLEFLevel.elixir_to_clef_level(:info) == :Information
    assert CLEFLevel.elixir_to_clef_level(:warn) == :Warning
    assert CLEFLevel.elixir_to_clef_level(:error) == :Error
  end

  test "converts CLEF levels to strings" do
    for level <- [:Verbose, :Debug, :Information, :Warning, :Error, :Fatal] do
      assert CLEFLevel.to_string(level) == Atom.to_string(level)
    end
  end
end
