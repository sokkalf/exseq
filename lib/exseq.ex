defmodule ExSeq do
  alias ExSeq.CLEFLevel

  @options [:seq_url, :api_key, :flush_interval, :batch_size, :max_buffer_size, :http_timeout]

  # Metadata that's either used for the CLEF fields or of no use in Seq.
  @internal_metadata [:time, :gl, :domain, :crash_reason, :report_cb, :mfa, :error_logger]

  ## :logger handler callbacks

  @doc false
  def adding_handler(%{id: id} = config) do
    with {:ok, options} <- validate_options(Map.get(config, :config, %{})),
         {:ok, _pid} <- start_flusher(id, options) do
      {:ok, Map.put(config, :config, options)}
    end
  end

  @doc false
  def changing_config(set_or_update, %{config: old_options}, %{id: id} = new_config) do
    options = Map.get(new_config, :config, %{})

    with {:ok, options} <- validate_options(options) do
      options = if set_or_update == :update, do: Map.merge(old_options, options), else: options
      GenServer.call(flusher(id), {:configure, Map.to_list(options)})
      {:ok, Map.put(new_config, :config, options)}
    end
  catch
    :exit, reason -> {:error, {:flusher_not_configured, reason}}
  end

  @doc false
  def removing_handler(%{id: id}) do
    case Registry.lookup(ExSeq.Registry, id) do
      [{pid, _}] -> DynamicSupervisor.terminate_child(ExSeq.FlusherSupervisor, pid)
      [] -> :ok
    end

    :ok
  end

  @doc false
  def log(%{meta: meta} = event, %{id: id}) do
    # Events from other nodes are logged there.
    if node(Map.get(meta, :gl, self())) == node() do
      GenServer.cast(flusher(id), {:receive, create_event(event)})
    end
  rescue
    # Raising would make :logger remove the handler.
    _ -> :ok
  end

  # Called by Logger.flush/0.
  @doc false
  def filesync(id) do
    GenServer.call(flusher(id), :flush, :timer.seconds(30))
  catch
    :exit, _ -> :ok
  end

  defp flusher(id), do: {:via, Registry, {ExSeq.Registry, id}}

  defp start_flusher(id, options) do
    spec = {ExSeq.Flusher, [name: flusher(id)] ++ Map.to_list(options)}

    case DynamicSupervisor.start_child(ExSeq.FlusherSupervisor, spec) do
      {:ok, pid} ->
        {:ok, pid}

      # Left over from a handler with the same id that wasn't removed cleanly.
      {:error, {:already_started, pid}} ->
        DynamicSupervisor.terminate_child(ExSeq.FlusherSupervisor, pid)
        start_flusher(id, options)

      {:error, reason} ->
        {:error, {:flusher_not_started, reason}}
    end
  catch
    :exit, _ -> {:error, {:not_started, :exseq}}
  end

  defp validate_options(options) when is_map(options) or is_list(options) do
    options = Map.new(options)

    case Map.keys(options) -- @options do
      [] -> {:ok, options}
      unknown -> {:error, {:invalid_options, unknown}}
    end
  end

  defp validate_options(options), do: {:error, {:invalid_options, options}}

  ## Events

  @doc false
  def create_event(%{level: level, meta: meta} = event) do
    %ExSeq.CLEFEvent{
      timestamp:
        DateTime.from_unix!(Map.get_lazy(meta, :time, &:logger.timestamp/0), :microsecond),
      message: format_message(event),
      exception: format_exception(meta[:crash_reason]),
      level: CLEFLevel.elixir_to_clef_level(level),
      properties: properties(meta)
    }
  end

  defp format_message(event) do
    truncate = Application.get_env(:logger, :truncate, 8096)
    event |> Logger.Formatter.format_event(truncate) |> IO.chardata_to_string()
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

  # Same as Elixir's Logger: :mfa becomes :module and :function, and :file is a
  # string.
  defp properties(meta) do
    properties =
      case meta do
        %{mfa: {module, function, arity}} ->
          Map.merge(%{module: module, function: "#{function}/#{arity}"}, meta)

        %{} ->
          meta
      end

    properties =
      case properties do
        %{file: file} when is_list(file) -> %{properties | file: List.to_string(file)}
        %{} -> properties
      end

    Map.drop(properties, @internal_metadata)
  end
end
