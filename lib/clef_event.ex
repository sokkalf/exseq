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
