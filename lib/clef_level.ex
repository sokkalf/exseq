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


  @spec to_string(t) :: String.t()
  def to_string(:Debug), do: "Debug"
  def to_string(:Verbose), do: "Verbose"
  def to_string(:Information), do: "Information"
  def to_string(:Warning), do: "Warning"
  def to_string(:Error), do: "Error"
  def to_string(:Fatal), do: "Fatal"
  def to_string(_), do: "Information"
end
