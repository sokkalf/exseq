defmodule ExSeq.Flusher do
  @moduledoc """
  Buffers events for an `ExSeq` handler and sends them to Seq in batches.

  A batch is sent once `:batch_size` events are buffered, and everything that's
  buffered is sent every `:flush_interval` seconds. Requests are made from a
  task, one at a time, so the Flusher keeps accepting events while waiting on
  Seq.

  If Seq can't be reached or responds with an error, the batch stays in the
  buffer and is retried on the next flush. The buffer holds at most
  `:max_buffer_size` events, dropping the oldest beyond that. Batches that Seq
  rejects as invalid (HTTP 400 or 413) are dropped.

  Everything buffered is also sent on `Logger.flush/0` and on shutdown.

  Flushers are started by `ExSeq` when a handler is added; there's no need to
  start one yourself.
  """

  # Leave time to send what's buffered on shutdown.
  use GenServer, shutdown: 10_000

  require Logger

  alias ExSeq.CLEFEvent

  defstruct buffer: :queue.new(),
            count: 0,
            in_flight: nil,
            retrying: false,
            draining: false,
            overflowing: false,
            flush_interval: :timer.seconds(5),
            batch_size: 50,
            max_buffer_size: 10_000,
            http_timeout: :timer.seconds(5),
            url: "http://localhost:5341/ingest/clef",
            api_key: nil

  def start_link(opts) do
    {name, config} = Keyword.pop(opts, :name)
    GenServer.start_link(__MODULE__, config, name: name)
  end

  @impl true
  def init(options) do
    ExSeq.mark_internal()
    state = configure(%__MODULE__{}, options)
    Process.flag(:trap_exit, true)
    tick(state.flush_interval)
    {:ok, state}
  end

  @impl true
  def handle_call(:flush, _from, state) do
    {:reply, :ok, flush_all(state)}
  end

  def handle_call({:configure, options}, _from, state) do
    {:reply, :ok, configure(state, options)}
  end

  @impl true
  def handle_cast({:receive, %CLEFEvent{} = msg}, state) do
    state =
      %{state | buffer: :queue.in(msg, state.buffer), count: state.count + 1}
      |> drop_oldest()
      |> maybe_flush()

    {:noreply, state}
  end

  @impl true
  def handle_info(:tick, state) do
    state = maybe_flush(%{state | draining: true})
    tick(state.flush_interval)
    {:noreply, state}
  end

  def handle_info({ref, result}, %{in_flight: {%Task{ref: ref}, batch}} = state) do
    Process.demonitor(ref, [:flush])
    state = handle_result(%{state | in_flight: nil}, batch, result)
    {:noreply, maybe_flush(state)}
  end

  def handle_info(
        {:DOWN, ref, :process, _, reason},
        %{in_flight: {%Task{ref: ref}, batch}} = state
      ) do
    result = {:retry, "request crashed: #{inspect(reason)}"}
    {:noreply, handle_result(%{state | in_flight: nil}, batch, result)}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    flush_all(state)
  end

  # Options that aren't given get their defaults.
  defp configure(state, options) do
    defaults = %__MODULE__{}
    batch_size = Keyword.get(options, :batch_size, defaults.batch_size)
    max_buffer_size = Keyword.get(options, :max_buffer_size, defaults.max_buffer_size)

    drop_oldest(%{
      state
      | url: Keyword.get(options, :seq_url, defaults.url),
        api_key: Keyword.get(options, :api_key, defaults.api_key),
        flush_interval: :timer.seconds(Keyword.get(options, :flush_interval, 5)),
        batch_size: batch_size,
        max_buffer_size: max(max_buffer_size, batch_size),
        http_timeout: Keyword.get(options, :http_timeout, defaults.http_timeout)
    })
  end

  defp drop_oldest(%{count: count, max_buffer_size: max} = state) when count > max do
    if not state.overflowing do
      Logger.warning(
        "The Seq buffer is full (#{max} events). Dropping the oldest events until Seq can be reached."
      )
    end

    drop_oldest(%{state | buffer: :queue.drop(state.buffer), count: count - 1, overflowing: true})
  end

  defp drop_oldest(state), do: state

  defp tick(interval), do: Process.send_after(self(), :tick, interval)

  # Sends the next batch from a task, one request at a time. After a tick,
  # everything buffered is sent; otherwise only full batches, and not while
  # Seq is failing.
  defp maybe_flush(%{in_flight: nil, count: count} = state) when count > 0 do
    if state.draining or (count >= state.batch_size and not state.retrying) do
      {batch, state} = take_batch(state)
      config = Map.take(state, [:url, :api_key, :http_timeout])

      task =
        Task.Supervisor.async_nolink(ExSeq.TaskSupervisor, fn ->
          ExSeq.mark_internal()
          post(batch, config)
        end)

      %{state | in_flight: {task, batch}}
    else
      state
    end
  end

  defp maybe_flush(%{count: 0} = state), do: %{state | draining: false}
  defp maybe_flush(state), do: state

  # Sends everything synchronously, stopping at the first failure.
  defp flush_all(state) do
    state |> await_in_flight() |> flush_sync()
  end

  defp await_in_flight(%{in_flight: nil} = state), do: state

  defp await_in_flight(%{in_flight: {task, batch}} = state) do
    result =
      case Task.yield(task, state.http_timeout * 2) || Task.shutdown(task, :brutal_kill) do
        {:ok, result} -> result
        _ -> {:retry, "timed out"}
      end

    handle_result(%{state | in_flight: nil}, batch, result)
  end

  defp flush_sync(%{count: 0} = state), do: state

  defp flush_sync(state) do
    {batch, state} = take_batch(state)
    result = post(batch, state)
    state = handle_result(state, batch, result)
    if match?({:retry, _}, result), do: state, else: flush_sync(state)
  end

  defp take_batch(state) do
    size = min(state.count, state.batch_size)
    {batch, rest} = :queue.split(size, state.buffer)
    {batch, %{state | buffer: rest, count: state.count - size}}
  end

  # A failed batch goes back to the front of the buffer, to be retried on the
  # next tick.
  defp handle_result(state, batch, {:retry, reason}) do
    if not state.retrying do
      Logger.warning("Couldn't send #{:queue.len(batch)} events to Seq (#{reason}). Will retry.")
    end

    buffer = :queue.join(batch, state.buffer)
    count = state.count + :queue.len(batch)
    drop_oldest(%{state | buffer: buffer, count: count, retrying: true, draining: false})
  end

  defp handle_result(state, batch, {:drop, status}) do
    Logger.warning("Seq rejected #{:queue.len(batch)} events with HTTP #{status}. Dropping them.")
    %{state | retrying: false}
  end

  defp handle_result(state, _batch, :ok), do: %{state | retrying: false, overflowing: false}

  defp post(batch, config) do
    case HTTPoison.post(
           config.url,
           messages_as_string_with_newline(:queue.to_list(batch)),
           headers(config.api_key),
           timeout: config.http_timeout,
           recv_timeout: config.http_timeout
         ) do
      {:ok, %HTTPoison.Response{status_code: status}} when status in 200..299 ->
        :ok

      # Seq rejected the payload itself, so retrying won't help.
      {:ok, %HTTPoison.Response{status_code: status}} when status in [400, 413] ->
        {:drop, status}

      {:ok, %HTTPoison.Response{status_code: status}} ->
        {:retry, "HTTP #{status}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:retry, inspect(reason)}
    end
  rescue
    # Also runs in the Flusher itself when flushing synchronously.
    exception -> {:retry, Exception.message(exception)}
  end

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

  defp headers(api_key) when api_key in [nil, ""] do
    [{"Content-Type", "application/vnd.serilog.clef"}]
  end

  defp headers(api_key), do: [{"X-Seq-ApiKey", api_key} | headers(nil)]
end
