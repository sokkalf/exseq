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

  # Waits for the request in flight, if any, to complete.
  defp await_idle(flusher) do
    if :sys.get_state(flusher).in_flight do
      Process.sleep(10)
      await_idle(flusher)
    end
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
    await_idle(flusher)
  end

  # Responds with the given statuses in turn, and reports each batch's messages.
  defp respond_with(bypass, statuses) do
    test = self()
    {:ok, statuses} = Agent.start_link(fn -> statuses end)

    Bypass.expect(bypass, "POST", "/ingest/clef", fn conn ->
      {events, conn} = lines(conn)
      send(test, {:events, Enum.map(events, & &1["@m"])})
      status = Agent.get_and_update(statuses, fn [status | rest] -> {status, rest} end)
      Plug.Conn.resp(conn, status, "")
    end)
  end

  test "retries failed batches, oldest first, on the next tick", %{bypass: bypass, url: url} do
    respond_with(bypass, [401, 503, 201, 201])
    flusher = start_flusher(seq_url: url, batch_size: 1)

    GenServer.cast(flusher, {:receive, event("one")})
    assert_receive {:events, ["one"]}

    # No new attempt until the next tick.
    GenServer.cast(flusher, {:receive, event("two")})
    refute_receive {:events, _}, 100

    await_idle(flusher)
    send(flusher, :tick)
    assert_receive {:events, ["one"]}
    refute_receive {:events, _}, 100

    await_idle(flusher)
    send(flusher, :tick)
    assert_receive {:events, ["one"]}
    assert_receive {:events, ["two"]}
    await_idle(flusher)
    assert %{count: 0, retrying: false} = :sys.get_state(flusher)
  end

  test "drops the oldest events when the buffer is full", %{bypass: bypass, url: url} do
    respond_with(bypass, [503, 201, 201])
    flusher = start_flusher(seq_url: url, batch_size: 1, max_buffer_size: 2)

    GenServer.cast(flusher, {:receive, event("one")})
    assert_receive {:events, ["one"]}
    GenServer.cast(flusher, {:receive, event("two")})
    GenServer.cast(flusher, {:receive, event("three")})

    await_idle(flusher)
    send(flusher, :tick)
    assert_receive {:events, ["two"]}
    assert_receive {:events, ["three"]}
    await_idle(flusher)
  end

  test "drops batches that Seq rejects as invalid", %{bypass: bypass, url: url} do
    respond_with(bypass, [400])
    flusher = start_flusher(seq_url: url, batch_size: 1)

    GenServer.cast(flusher, {:receive, event("one")})
    assert_receive {:events, ["one"]}
    await_idle(flusher)
    assert %{count: 0, retrying: false} = :sys.get_state(flusher)
  end

  test "inspects properties that fail to encode", %{bypass: bypass, url: url} do
    test = self()

    Bypass.expect_once(bypass, "POST", "/ingest/clef", fn conn ->
      {events, conn} = lines(conn)
      send(test, {:events, events})
      Plug.Conn.resp(conn, 201, "")
    end)

    flusher = start_flusher(seq_url: url, batch_size: 2)
    bad = %ExSeq.Test.Derived{value: {:not, :encodable}}
    good = %CLEFEvent{level: :Information, message: "good"}

    GenServer.cast(flusher, {:receive, %{good | properties: [bad: bad, ok: 1]}})
    GenServer.cast(flusher, {:receive, good})

    assert_receive {:events, [first, %{"@m" => "good"}]}
    assert %{"@m" => "good", "bad" => inspected, "ok" => 1} = first
    assert inspected == inspect(bad)
    await_idle(flusher)
  end

  test "sends the API key only when one is configured", %{bypass: bypass, url: url} do
    test = self()

    Bypass.expect(bypass, "POST", "/ingest/clef", fn conn ->
      send(test, {:api_key, Plug.Conn.get_req_header(conn, "x-seq-apikey")})
      Plug.Conn.resp(conn, 201, "")
    end)

    for {opts, expected} <- [{[], []}, {[api_key: ""], []}, {[api_key: "secret"], ["secret"]}] do
      flusher = start_flusher([seq_url: url, batch_size: 1] ++ opts)
      GenServer.cast(flusher, {:receive, event("one")})
      assert_receive {:api_key, ^expected}
      stop_supervised!(ExSeq.Flusher)
    end
  end

  test "doesn't block while a request is in flight", %{bypass: bypass, url: url} do
    test = self()

    Bypass.expect(bypass, "POST", "/ingest/clef", fn conn ->
      send(test, {:waiting, self()})

      receive do
        :respond -> Plug.Conn.resp(conn, 201, "")
      end
    end)

    flusher = start_flusher(seq_url: url, batch_size: 1)
    GenServer.cast(flusher, {:receive, event("one")})
    assert_receive {:waiting, handler}

    # One request at a time; the rest is buffered meanwhile.
    GenServer.cast(flusher, {:receive, event("two")})
    assert %{count: 1, in_flight: {_, _}} = :sys.get_state(flusher)

    send(handler, :respond)
    assert_receive {:waiting, handler}
    send(handler, :respond)
    await_idle(flusher)
  end

  test "gives up on requests that time out" do
    # Accepts connections but never responds.
    {:ok, socket} = :gen_tcp.listen(0, active: false)
    {:ok, port} = :inet.port(socket)

    flusher = start_flusher(seq_url: "http://localhost:#{port}", batch_size: 1, http_timeout: 100)
    GenServer.cast(flusher, {:receive, event("one")})
    await_idle(flusher)
    assert %{count: 1, retrying: true} = :sys.get_state(flusher)
  end

  test "flushes everything on request", %{bypass: bypass, url: url} do
    respond_with(bypass, [201, 201])
    flusher = start_flusher(seq_url: url, batch_size: 2)

    for message <- ["one", "two", "three"],
        do: GenServer.cast(flusher, {:receive, event(message)})

    assert_receive {:events, ["one", "two"]}

    assert GenServer.call(flusher, :flush) == :ok
    assert_received {:events, ["three"]}
  end

  test "flushes on shutdown", %{bypass: bypass, url: url} do
    respond_with(bypass, [201])
    flusher = start_flusher(seq_url: url)

    GenServer.cast(flusher, {:receive, event("one")})
    stop_supervised!(ExSeq.Flusher)

    refute Process.alive?(flusher)
    assert_received {:events, ["one"]}
  end

  test "sends nothing when there's nothing to flush", %{url: url} do
    # Bypass fails the test on any unexpected request.
    flusher = start_flusher(seq_url: url)
    send(flusher, :tick)
    :sys.get_state(flusher)
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
