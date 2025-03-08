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
    {:ok, flusher} = GenServer.start_link(ExSeq.Flusher, config, name: ExSeq.Flusher)
    {:ok, %__MODULE__{flusher: flusher, level: level}}
  end

  @impl true
  def handle_event({_level, gl, {Logger, _, _, _}}, state)
      when node(gl) != node() do
    {:ok, state}
  end

  def handle_event({level, _group_leader, {Logger, message, timestamp, metadata}}, state) do
    level_order = %{
      debug: 0,
      info: 1,
      warn: 2,
      error: 3
    }

    if level_order[level] >= level_order[state.level] do
      create_event(level, message, timestamp, metadata)
      |> send_event()
    end

    {:ok, state}
  end

  def handle_event(:flush, state) do
    IO.puts("Flush event")
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

  defp create_event(level, message, timestamp, metadata) do
    ts =
      case Keyword.get(metadata, :time) do
        nil ->
          {{year, month, day}, {hour, minute, second, millisecond}} = timestamp
          NaiveDateTime.new!(year, month, day, hour, minute, second, millisecond * 1000)

        t ->
          DateTime.from_unix!(t, :microsecond)
      end

    metadata =
      Keyword.delete(metadata, :time)
      |> Keyword.delete(:erl_level)
      |> Keyword.delete(:gl)
      |> Keyword.delete(:domain)

    {message, exception} = case String.split(message, "\n", parts: 2) do
      [message, exception] ->
        {message, exception}
      [message] ->
        {message, nil}
    end

    %ExSeq.CLEFEvent{
      timestamp: ts,
      message: message,
      exception: exception,
      level: CLEFLevel.elixir_to_clef_level(level),
      properties: metadata
    }
  end

  defp send_event(clef_event) do
    GenServer.cast(ExSeq.Flusher, {:receive, clef_event})
  end
end
