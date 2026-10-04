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
    # :url and :flush_interval_seconds are the old, undocumented names.
    url = args[:seq_url] || args[:url] || "http://localhost:5341/ingest/clef"
    api_key = Keyword.get(args, :api_key, "")
    flush_interval = :timer.seconds(args[:flush_interval] || args[:flush_interval_seconds] || 5)
    batch_size = Keyword.get(args, :batch_size, 50)

    state = %__MODULE__{
      url: url,
      api_key: api_key,
      flush_interval: flush_interval,
      batch_size: batch_size
    }

    tick(state.flush_interval)
    {:ok, state}
  end

  @impl true
  def handle_cast({:receive, %CLEFEvent{} = msg}, state) do
    # Newest first; reversed when sending.
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

    state =
      if length(state.retry_buffer) > 0 and length(state.messages) == 0 do
        %{state | messages: state.retry_buffer, retry_buffer: []}
      else
        state
      end

    tick(state.flush_interval)
    {:noreply, state}
  end

  defp tick(interval), do: Process.send_after(self(), :tick, interval)

  defp messages_as_string_with_newline(messages) do
    messages
    |> Enum.flat_map(&encode_event/1)
    |> Enum.join("\n")
  end

  # Encode events one at a time, so a bad event can't take the batch down with
  # it. If encoding fails, retry with the offending properties inspected, and
  # drop the event if that fails too.
  defp encode_event(event) do
    [Jason.encode!(event)]
  rescue
    _ ->
      try do
        properties = Enum.map(event.properties, fn {k, v} -> {k, encodable(v)} end)
        [Jason.encode!(%{event | properties: properties})]
      rescue
        _ -> []
      end
  end

  defp encodable(value) do
    case Jason.encode(value) do
      {:ok, _} -> value
      {:error, _} -> inspect(value)
    end
  rescue
    _ -> inspect(value)
  end

  defp flush(state) do
    headers = [
      {"Content-Type", "application/vnd.serilog.clef"},
      {"X-Seq-ApiKey", state.api_key}
    ]

    case HTTPoison.post(
           state.url,
           messages_as_string_with_newline(Enum.reverse(state.messages)),
           headers
         ) do
      {:ok, %HTTPoison.Response{status_code: status}} when status in 200..299 ->
        %{state | messages: []}

      _error ->
        %{state | retry_buffer: state.messages, messages: []}
    end
  end
end
