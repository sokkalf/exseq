# ExSeq

**ExSeq** is an Elixir [Logger](https://hexdocs.pm/logger/Logger.html) handler for sending logs to [Seq](https://datalust.co/seq) using the [Compact Log Event Format (CLEF)](https://clef-json.org).

## Features

- Minimal configuration required
- Converts Elixir log messages and metadata into CLEF events
- Sends events asynchronously through a GenServer
- Filters log messages based on minimum log level

## Installation

Add `exseq` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:exseq, "~> 0.1.2"}
  ]
end
```

Then run:

```sh
mix deps.get
```

## Configuration

ExSeq is a [`:logger` handler](https://hexdocs.pm/logger/Logger.html#module-erlang-otp-handlers). Configure it in your `config.exs`:

```elixir
config :my_app, :logger, [
  {:handler, :seq, ExSeq,
   %{
     level: :info,
     config: %{
       seq_url: "http://localhost:5341/ingest/clef",
       api_key: "YOUR_SEQ_API_KEY"
     }
   }}
]
```

and add it when your application starts:

```elixir
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    Logger.add_handlers(:my_app)
    # ...
  end
end
```

You can also add it at runtime with `:logger.add_handler(:seq, ExSeq, %{config: %{...}})`.

`level` sets the minimum level to send to Seq, like for any other handler. The options under `config` are:

| Option            | Default                              | Description                                                                 |
| ----------------- | ------------------------------------ | --------------------------------------------------------------------------- |
| `seq_url`         | `"http://localhost:5341/ingest/clef"` | The CLEF ingestion endpoint of your Seq server.                            |
| `api_key`         | none                                 | Your Seq API key, if Seq requires one.                                      |
| `flush_interval`  | `5`                                  | Seconds between flushes. Buffered events are sent at least this often.     |
| `batch_size`      | `50`                                 | Events are sent as soon as this many are buffered.                          |
| `max_buffer_size` | `10000`                              | Events kept while Seq is unreachable. The oldest are dropped beyond this.  |
| `http_timeout`    | `5000`                               | Connect and receive timeout for requests to Seq, in milliseconds.          |

### Upgrading from 0.1

Earlier versions were a Logger backend, set up with `config :logger, backends: [ExSeq]` and `config :logger, ExSeq, ...`. Remove both, and move the options into the handler config as above, with `level` at the top level and the rest under `config`. `url` and `flush_interval_seconds` are now `seq_url` and `flush_interval`.

## How It Works

1. **`ExSeq`** implements the Erlang `:logger` handler callbacks. Adding a handler starts an `ExSeq.Flusher` for it.
2. `:logger` passes the handler every event at or above its level, and `ExSeq` converts it to a [CLEFEvent](./lib/clef_event.ex) struct.
3. The event is then sent asynchronously to the handler's `ExSeq.Flusher` GenServer for batching and sending to Seq.

## Usage

After adding the handler, just log as usual in Elixir:

```elixir
Logger.debug("This is a debug log")  # Will be filtered out if :level >= :info
Logger.info("An info-level message")
Logger.warning("A warning")
Logger.error("An error occurred!")
```

Each message you log is converted into a CLEF event and sent to Seq. If you’ve configured your `seq_url` and (optionally) an `api_key` correctly, you should see your events in the Seq UI under the configured ingestion endpoint.

## Example

```elixir
defmodule MyApp do
  require Logger

  def run do
    Logger.info("Starting application", foo: "bar")
    # ...
    Logger.error("Oops, something went wrong!", user_id: 123)
  end
end
```

You can then start your application (e.g. via `iex -S mix`) and see the logs in Seq if everything is configured properly.

## Notes

- Events are buffered by an `ExSeq.Flusher`, a GenServer running under ExSeq's own supervisor, and sent to Seq in batches from a separate task. If Seq can't be reached, they're kept (up to `max_buffer_size`) and retried on the next flush. Buffered events are also sent on shutdown and on `Logger.flush/0`.
- Timestamps come from the Logger `:time` metadata and are sent in UTC.
- Log levels map to CLEF levels as follows:

  | Logger                              | CLEF          |
  | ----------------------------------- | ------------- |
  | `:debug`                            | `Debug`       |
  | `:info`, `:notice`                  | `Information` |
  | `:warning`                          | `Warning`     |
  | `:error`                            | `Error`       |
  | `:critical`, `:alert`, `:emergency` | `Fatal`       |
- Crash reasons (the `:crash_reason` metadata) are sent as the event's exception. All other metadata is sent as event properties.

## Contributing

1. Fork the repository.
2. Create a feature branch.
3. Make your changes and write tests if necessary.
4. Submit a Pull Request.

## License

This project is [MIT Licensed](./LICENSE).
