defmodule ExSeq do
  @behaviour :gen_event

  alias ExSeq.CLEFLevel

  defstruct [
    :flusher,
    :level
  ]

  def start_link(_args) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  @impl true
  def init(_args) do
    config = Application.get_env(:logger, __MODULE__, [])
    level = Keyword.get(config, :level, :info)
    # The Flusher runs under ExSeq.Supervisor rather than linked to Logger.
    {:ok, %__MODULE__{flusher: ExSeq.Flusher, level: level}}
  end

  @impl true
  def handle_event({_level, gl, {Logger, _, _, _}}, state)
      when node(gl) != node() do
    {:ok, state}
  end

  def handle_event({level, _group_leader, {Logger, message, timestamp, metadata}}, state) do
    if :logger.compare_levels(erlang_level(level), erlang_level(state.level)) != :lt do
      create_event(level, message, timestamp, metadata)
      |> send_event(state.flusher)
    end

    {:ok, state}
  end

  # Sent by Logger.flush/0.
  def handle_event(:flush, state) do
    try do
      GenServer.call(state.flusher, :flush, :timer.seconds(30))
    catch
      :exit, _ -> :ok
    end

    {:ok, state}
  end

  def handle_event(_, state) do
    {:ok, state}
  end

  # Logger.compare_levels/2 would warn about :warn being deprecated.
  defp erlang_level(:warn), do: :warning
  defp erlang_level(level), do: level

  @impl true
  def handle_info(_, state) do
    {:ok, state}
  end

  @impl true
  def handle_call({:configure, _options}, state) do
    {:ok, :ok, state}
  end

  # Elixir puts the reason and stacktrace of crashes in :crash_reason.
  defp format_exception({{:nocatch, value}, stacktrace}) do
    Exception.format(:throw, value, stacktrace)
  end

  defp format_exception({exception, stacktrace}) when is_exception(exception) do
    Exception.format(:error, exception, stacktrace)
  end

  defp format_exception({reason, stacktrace}) when is_list(stacktrace) do
    Exception.format(:exit, reason, stacktrace)
  end

  defp format_exception(_), do: nil

  @doc false
  def create_event(level, message, timestamp, metadata) do
    ts =
      case Keyword.get(metadata, :time) do
        nil ->
          {{year, month, day}, {hour, minute, second, millisecond}} = timestamp
          NaiveDateTime.new!(year, month, day, hour, minute, second, millisecond * 1000)

        t ->
          DateTime.from_unix!(t, :microsecond)
      end

    # Logger translates levels for backends (e.g. :critical to :error), but
    # keeps the original in :erl_level.
    level = Keyword.get(metadata, :erl_level, level)
    exception = format_exception(metadata[:crash_reason])

    metadata =
      Keyword.delete(metadata, :time)
      |> Keyword.delete(:erl_level)
      |> Keyword.delete(:gl)
      |> Keyword.delete(:domain)
      |> Keyword.delete(:crash_reason)

    %ExSeq.CLEFEvent{
      timestamp: ts,
      message: IO.chardata_to_string(message),
      exception: exception,
      level: CLEFLevel.elixir_to_clef_level(level),
      properties: metadata
    }
  end

  defp send_event(clef_event, flusher) do
    GenServer.cast(flusher, {:receive, clef_event})
  end
end
