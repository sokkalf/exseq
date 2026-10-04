defmodule ExSeq.Flusher do
  use GenServer

  alias ExSeq.CLEFEvent

  defstruct buffer: :queue.new(),
            count: 0,
            retrying: false,
            flush_interval: :timer.seconds(5),
            batch_size: 50,
            max_buffer_size: 10_000,
            url: "http://localhost:5341/ingest/clef",
            api_key: nil

  @impl true
  def init(args) do
    # :url and :flush_interval_seconds are the old, undocumented names.
    url = args[:seq_url] || args[:url] || "http://localhost:5341/ingest/clef"
    api_key = Keyword.get(args, :api_key)
    flush_interval = :timer.seconds(args[:flush_interval] || args[:flush_interval_seconds] || 5)
    batch_size = Keyword.get(args, :batch_size, 50)
    max_buffer_size = Keyword.get(args, :max_buffer_size, 10_000)

    state = %__MODULE__{
      url: url,
      api_key: api_key,
      flush_interval: flush_interval,
      batch_size: batch_size,
      max_buffer_size: max(max_buffer_size, batch_size)
    }

    tick(state.flush_interval)
    {:ok, state}
  end

  @impl true
  def handle_cast({:receive, %CLEFEvent{} = msg}, state) do
    state =
      %{state | buffer: :queue.in(msg, state.buffer), count: state.count + 1}
      |> drop_oldest()

    # While Seq is failing, wait for the next tick instead of retrying on
    # every event.
    state =
      if state.count >= state.batch_size and not state.retrying do
        flush(state)
      else
        state
      end

    {:noreply, state}
  end

  @impl true
  def handle_info(:tick, state) do
    state = flush_all(state)
    tick(state.flush_interval)
    {:noreply, state}
  end

  defp drop_oldest(%{count: count, max_buffer_size: max} = state) when count > max do
    %{state | buffer: :queue.drop(state.buffer), count: count - 1}
  end

  defp drop_oldest(state), do: state

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

  defp flush_all(state) do
    state = flush(state)
    if state.count > 0 and not state.retrying, do: flush_all(state), else: state
  end

  defp flush(%{count: 0} = state), do: state

  # Sends the oldest batch_size events. They stay at the front of the buffer
  # until Seq accepts them.
  defp flush(state) do
    size = min(state.count, state.batch_size)
    {batch, rest} = :queue.split(size, state.buffer)
    sent = %{state | buffer: rest, count: state.count - size, retrying: false}

    case HTTPoison.post(
           state.url,
           messages_as_string_with_newline(:queue.to_list(batch)),
           headers(state.api_key)
         ) do
      {:ok, %HTTPoison.Response{status_code: status}} when status in 200..299 ->
        sent

      # Seq rejected the payload itself, so retrying won't help.
      {:ok, %HTTPoison.Response{status_code: status}} when status in [400, 413] ->
        sent

      _error ->
        %{state | retrying: true}
    end
  end

  defp headers(api_key) when api_key in [nil, ""] do
    [{"Content-Type", "application/vnd.serilog.clef"}]
  end

  defp headers(api_key), do: [{"X-Seq-ApiKey", api_key} | headers(nil)]
end
