defmodule ExSeq.Flusher do
  use GenServer

  alias ExSeq.CLEFEvent

  defstruct messages: [],
            flush_interval: :timer.seconds(5),
            batch_size: 50,
            retry_buffer: [],
            url: "http://localhost:5341/ingest/clef",
            api_key: ""

  @impl true
  def init(args) do
    url = Keyword.get(args, :url, "http://localhost:5341/ingeest/clef")
    state = %__MODULE__{url: url, api_key: api_key}
    api_key = Keyword.get(args, :api_key, "")
    tick(state.flush_interval)
    {:ok, state}
  end

  @impl true
  def handle_cast({:receive, %CLEFEvent{} = msg}, state) do
    state = %{state | messages: [msg | state.messages]}

    state =
      if length(state.messages) >= state.batch_size do
        flush(state)
      else
        state
      end

    {:noreply, state}
  end

  @impl true
  def handle_info(:tick, state) do
    state = flush(state)
    state = if length(state.retry_buffer) > 0 and length(state.messages) == 0 do
      %{state | messages: state.retry_buffer, retry_buffer: []}
    else
      state
    end
    tick(state.flush_interval)
    {:noreply, state}
  end

  defp tick(interval), do: Process.send_after(self(), :tick, interval)

  defp messages_as_string_with_newline(messages) do
    Enum.map(messages, &Jason.encode!(&1))
    |> Enum.join("\n")
  end

  defp flush(state) do
    headers = [
      {"Content-Type", "application/vnd.serilog.clef"},
      {"X-Seq-ApiKey", state.api_key}
    ]

    case HTTPoison.post(
           state.url,
           messages_as_string_with_newline(state.messages),
           headers
         ) do
      {:ok, _} ->
        %{state | messages: []}

      {:error, %HTTPoison.Error{reason: _reason}} ->
        %{state | retry_buffer: state.messages, messages: []}
    end
  end
end
