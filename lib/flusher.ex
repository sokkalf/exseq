defmodule ExSeq.Flusher do
  use GenServer

  alias ExSeq.CLEFEvent

  defstruct messages: [],
            flush_interval: :timer.seconds(5),
            batch_size: 50,
            retry_buffer: []

  @impl true
  def init(_args) do
    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_cast({:receive, %CLEFEvent{} = msg}, state) do
    IO.puts(Jason.encode!(msg))
    {:noreply, state}
  end
end
