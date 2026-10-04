defmodule ExSeq.Test.Derived do
  @moduledoc false

  # Compiled before protocol consolidation, unlike modules in test files.
  @derive Jason.Encoder
  defstruct [:value]
end
