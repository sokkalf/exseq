defmodule ExSeq do
  use GenServer

  def start_link(_args) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def init(_args) do
    {:ok, nil}
  end

  def handle_event({_level, gl, {Logger, _, _, _}}, state)
      when node(gl) != node() do
    {:ok, state}
  end

  def handle_event({level, _group_leader, {Logger, message, timestamp, metadata}}, state) do
    clef_event = %ExSeq.CLEFEvent{
      timestamp: timestamp,
      message: message,
      level: level,
      properties: metadata
    }

    IO.inspect(clef_event)

    {:ok, state}
  end

  def handle_event(:flush, state) do
    IO.puts "Flush event"
    {:ok, state}
  end

  def handle_info(msg, state) do
    IO.inspect(msg)
    {:ok, state}
  end
end
