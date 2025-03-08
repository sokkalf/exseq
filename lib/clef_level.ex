defmodule ExSeq.CLEFLevel do
  @moduledoc """
  Enumerates the valid CLEF log levels.
  """

  @type t ::
          :Debug
          | :Verbose
          | :Information
          | :Warning
          | :Error
          | :Fatal
end
