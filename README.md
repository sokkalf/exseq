# ExSeq

**ExSeq** is an Elixir [Logger](https://hexdocs.pm/logger/Logger.html) backend for sending logs to [Seq](https://datalust.co/seq) using the [Compact Log Event Format (CLEF)](https://clef-json.org).

## Features

- Minimal configuration required
- Converts Elixir log messages and metadata into CLEF events
- Sends events asynchronously through a GenServer
- Filters log messages based on minimum log level

## Installation

Add `ex_seq` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ex_seq, "~> 0.1.0"}
  ]
end
```

Then run:

```sh
mix deps.get
```

## Configuration

In your `config.exs`, set up the `logger` to use `ExSeq`:

```elixir
config :logger,
  backends: [:console, ExSeq],
  level: :info

config :logger, ExSeq,
  level: :info,
  seq_url: "http://localhost:5341/ingest/clef",
  api_key: "YOUR_SEQ_API_KEY",
```

- **`level`** sets the minimum level for sending to Seq. Levels below this are ignored.
- **`seq_url`** is the endpoint of your Seq server.
- **`api_key`** is your Seq API key if required for authentication (optional if Seq isn’t secured).

## How It Works

1. **`ExSeq`** implements the `:gen_event` behavior, which the Elixir `Logger` uses for backends.
2. When a log event arrives, `ExSeq` checks if its level is >= the configured minimum. If so, it converts the event to a [CLEFEvent](./lib/ex_seq/clef_event.ex) struct.
3. The event is then sent asynchronously to the `ExSeq.Flusher` GenServer for batching and sending to Seq.

## Usage

After adding `ExSeq` to your logger backends and setting your `:level`, just log as usual in Elixir:

```elixir
Logger.debug("This is a debug log")  # Will be filtered out if :level >= :info
Logger.info("An info-level message")
Logger.warn("A warning")
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

- `ExSeq` uses a custom minimal `:gen_server` (the `Flusher`) to batch events and send them in the background.
- Timestamps are pulled from the Elixir logger metadata if present, or from the default Erlang timestamp.
- The log level is converted from Elixir’s levels (`:debug`, `:info`, `:warn`, `:error`) to CLEF’s equivalent (`Debug`, `Information`, `Warning`, `Error`) via `CLEFLevel.elixir_to_clef_level/1`.

## Contributing

1. Fork the repository.
2. Create a feature branch.
3. Make your changes and write tests if necessary.
4. Submit a Pull Request.

## License

This project is [MIT Licensed](./LICENSE).
