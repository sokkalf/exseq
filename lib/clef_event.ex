defmodule ExSeq.CLEFEvent do
  @moduledoc """
  Represents a Compact Log Event Format (CLEF) log event.
  """

  alias ExSeq.CLEFLevel

  @enforce_keys [:level]
  defstruct [
    :timestamp,
    :message,
    :exception,
    :level,
    :trace_id,
    :span_id,
    :span_start,
    :span_kind,
    :resource_attributes,
    :parent_span_id,
    properties: %{}
  ]

  @typedoc """
  CLEF event

  * `timestamp` – a `DateTime` (or `NaiveDateTime`) for the log time.
  * `message` – the main log message string.
  * `exception` – an exception stacktrace or error details.
  * `level` – one of the `ExSeq.CLEFLevel` variants.
  * `trace_id` – a string trace ID for distributed tracing.
  * `span_id` – a string span ID for distributed tracing.
  * `span_start` – a `DateTime` marking when the span began.
  * `span_kind` – a string describing the kind of span (client, server, etc.).
  * `resource_attributes` – a map of key/value pairs describing the resource.
  * `parent_span_id` – a span ID for the parent span (if any).
  * `properties` – additional arbitrary key/value pairs.
  """
  @type t :: %__MODULE__{
          timestamp: DateTime.t() | NaiveDateTime.t() | nil,
          message: String.t() | nil,
          exception: String.t() | nil,
          level: CLEFLevel.t(),
          trace_id: String.t() | nil,
          span_id: String.t() | nil,
          span_start: DateTime.t() | NaiveDateTime.t() | nil,
          span_kind: String.t() | nil,
          resource_attributes: map() | nil,
          parent_span_id: String.t() | nil,
          properties: map()
        }
end

defimpl Jason.Encoder, for: ExSeq.CLEFEvent do
  alias ExSeq.CLEFLevel

  defp sanitize_metadata(value) when is_map(value) and not is_struct(value) do
    Enum.into(value, %{}, fn {k, v} -> {k, sanitize_metadata(v)} end)
  end

  defp sanitize_metadata(value) when is_struct(value) do
    # Dirty fallback hack
    try do
      Jason.encode!(value)
      value
    rescue
      _ -> inspect(value)
    end
  end

  defp sanitize_metadata(value) when is_list(value) do
    Enum.map(value, &sanitize_metadata/1)
  end

  defp sanitize_metadata(value) when is_tuple(value) do
    inspect(value)
  end

  defp sanitize_metadata(value) when is_pid(value) do
    inspect(value)
  end

  defp sanitize_metadata(value) when is_atom(value) do
    Atom.to_string(value)
  end

  defp sanitize_metadata(value) when is_binary(value), do: value
  defp sanitize_metadata(value), do: inspect(value)

  def encode(%ExSeq.CLEFEvent{} = event, opts) do
    # Transform the struct into a map with the CLEF fields:
    clef_map = %{
      "@t" => event.timestamp,
      "@m" => event.message,
      "@x" => event.exception,
      "@l" => CLEFLevel.to_string(event.level),
      "@tr" => event.trace_id,
      "@sp" => event.span_id,
      "@st" => event.span_start,
      "@sk" => event.span_kind,
      "@ra" => event.resource_attributes,
      "@ps" => event.parent_span_id
    }

    # Add user-defined properties into the top-level map:
    props = event.properties |> Enum.into(%{})
    merged = Map.merge(clef_map, props || %{})

    cleaned =
      merged
      |> Enum.reject(fn {_key, value} ->
        is_nil(value) or value == ""
      end)
      |> Enum.into(%{})
      |> sanitize_metadata()

    Jason.Encode.map(cleaned, opts)
  end
end
