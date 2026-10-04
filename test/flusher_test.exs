defmodule ExSeq.FlusherTest do
  use ExUnit.Case, async: true

  alias ExSeq.CLEFEvent

  setup do
    bypass = Bypass.open()
    {:ok, bypass: bypass, url: "http://localhost:#{bypass.port}/ingest/clef"}
  end

  defp start_flusher(opts) do
    opts = Keyword.merge([flush_interval_seconds: 3600], opts)

    start_supervised!(%{
      id: ExSeq.Flusher,
      start: {GenServer, :start_link, [ExSeq.Flusher, opts]}
    })
  end

  defp event(message), do: %CLEFEvent{level: :Information, message: message}

  defp lines(conn) do
    {:ok, body, conn} = Plug.Conn.read_body(conn)
    {body |> String.split("\n") |> Enum.map(&Jason.decode!/1), conn}
  end

  test "sends a batch once batch_size events are buffered", %{bypass: bypass, url: url} do
    test = self()

    Bypass.expect_once(bypass, "POST", "/ingest/clef", fn conn ->
      assert Plug.Conn.get_req_header(conn, "content-type") == ["application/vnd.serilog.clef"]
      {events, conn} = lines(conn)
      send(test, {:events, Enum.map(events, & &1["@m"])})
      Plug.Conn.resp(conn, 201, "")
    end)

    flusher = start_flusher(url: url, batch_size: 2)
    GenServer.cast(flusher, {:receive, event("one")})
    refute_receive {:events, _}, 100
    GenServer.cast(flusher, {:receive, event("two")})

    assert_receive {:events, messages}
    assert Enum.sort(messages) == ["one", "two"]
    :sys.get_state(flusher)
  end
end
