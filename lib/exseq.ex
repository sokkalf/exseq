defmodule ExSeq do
  @behaviour :gen_event

  def start_link(_args) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  @impl true
  def init(_args) do
    {:ok, nil}
  end

  @impl true
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

  def handle_event(_, state) do
    {:ok, state}
  end

  @impl true
  def handle_info(_, state) do
    {:ok, state}
  end

  @impl true
  def handle_call({:configure, _options}, state) do
    {:ok, :ok, state}
  end
end
