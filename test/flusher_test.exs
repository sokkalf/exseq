defmodule ExSeq.FlusherTest do
  use ExUnit.Case, async: true

  alias ExSeq.CLEFEvent

  setup do
    bypass = Bypass.open()
    {:ok, bypass: bypass, url: "http://localhost:#{bypass.port}/ingest/clef"}
  end

  defp start_flusher(opts) do
    opts = Keyword.merge([flush_interval: 3600], opts)

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

  test "sends a batch, in order, once batch_size events are buffered", %{bypass: bypass, url: url} do
    test = self()

    Bypass.expect_once(bypass, "POST", "/ingest/clef", fn conn ->
      assert Plug.Conn.get_req_header(conn, "content-type") == ["application/vnd.serilog.clef"]
      {events, conn} = lines(conn)
      send(test, {:events, Enum.map(events, & &1["@m"])})
      Plug.Conn.resp(conn, 201, "")
    end)

    flusher = start_flusher(seq_url: url, batch_size: 2)
    GenServer.cast(flusher, {:receive, event("one")})
    refute_receive {:events, _}, 100
    GenServer.cast(flusher, {:receive, event("two")})

    assert_receive {:events, ["one", "two"]}
    :sys.get_state(flusher)
  end

  test "keeps a batch for retry when Seq responds with an error", %{bypass: bypass, url: url} do
    Bypass.expect_once(bypass, "POST", "/ingest/clef", &Plug.Conn.resp(&1, 401, ""))

    flusher = start_flusher(seq_url: url, batch_size: 1)
    GenServer.cast(flusher, {:receive, event("one")})

    assert %{messages: [], retry_buffer: [%CLEFEvent{message: "one"}]} = :sys.get_state(flusher)
  end

  describe "config" do
    test "reads the documented keys" do
      flusher = start_flusher(seq_url: "http://seq/ingest/clef", flush_interval: 2)
      assert %{url: "http://seq/ingest/clef", flush_interval: 2000} = :sys.get_state(flusher)
    end

    test "still accepts the old key names" do
      flusher =
        start_flusher(
          url: "http://seq/ingest/clef",
          flush_interval: nil,
          flush_interval_seconds: 2
        )

      assert %{url: "http://seq/ingest/clef", flush_interval: 2000} = :sys.get_state(flusher)
    end

    test "defaults to a local Seq" do
      flusher = start_flusher([])
      assert :sys.get_state(flusher).url == "http://localhost:5341/ingest/clef"
    end
  end
end
