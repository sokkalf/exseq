defmodule ExSeqTest do
  use ExUnit.Case, async: true

  alias ExSeq.CLEFEvent

  @time 1_735_787_045_123_456

  defp log_event(level, msg, meta \\ %{}) do
    %{level: level, msg: msg, meta: Map.merge(%{time: @time, pid: self()}, meta)}
  end

  describe "create_event/1" do
    test "builds an event from a log event" do
      event =
        ExSeq.create_event(log_event(:info, {:string, ["hello", ?\s, "world"]}, %{foo: "bar"}))

      assert %CLEFEvent{
               level: :Information,
               message: "hello world",
               exception: nil,
               timestamp: ~U[2025-01-02 03:04:05.123456Z]
             } = event

      assert event.properties == %{foo: "bar", pid: self()}
    end

    test "formats reports and format strings" do
      assert ExSeq.create_event(log_event(:info, {~c"~p and ~s", [:a, "b"]})).message ==
               ":a and b"

      assert ExSeq.create_event(log_event(:info, {:report, %{a: 1}})).message == "[a: 1]"
    end

    test "uses the event's level" do
      for {level, clef_level} <- [warning: :Warning, notice: :Information, critical: :Fatal] do
        assert ExSeq.create_event(log_event(level, {:string, "hi"})).level == clef_level
      end
    end

    test "accepts chardata with codepoints above 255" do
      event = ExSeq.create_event(log_event(:info, {:string, [~c"blåbær ", 0x1F600, "!"]}))
      assert event.message == "blåbær 😀!"
    end

    test "keeps multi-line messages whole" do
      event = ExSeq.create_event(log_event(:info, {:string, "line one\nline two"}))
      assert %CLEFEvent{message: "line one\nline two", exception: nil} = event
    end

    test "formats the exception from :crash_reason" do
      stacktrace = [{Foo, :bar, 1, [file: ~c"lib/foo.ex", line: 3]}]

      for {reason, expected} <- [
            {{%RuntimeError{message: "boom"}, stacktrace}, "** (RuntimeError) boom"},
            {{{:nocatch, :ball}, stacktrace}, "** (throw) :ball"},
            {{:killed, stacktrace}, "** (exit) killed"}
          ] do
        event =
          ExSeq.create_event(log_event(:error, {:string, "crashed"}, %{crash_reason: reason}))

        assert event.message == "crashed"
        assert event.exception =~ expected
        assert event.exception =~ "lib/foo.ex:3: Foo.bar/1"
        refute Map.has_key?(event.properties, :crash_reason)
      end
    end

    test "converts and removes metadata like Elixir's Logger" do
      meta = %{
        gl: self(),
        domain: [:elixir],
        report_cb: &inspect/1,
        mfa: {Foo, :bar, 2},
        file: ~c"lib/foo.ex",
        line: 3
      }

      event = ExSeq.create_event(log_event(:info, {:string, "hi"}, meta))

      assert event.properties == %{
               pid: self(),
               module: Foo,
               function: "bar/2",
               file: "lib/foo.ex",
               line: 3
             }
    end
  end

  describe "handler" do
    setup do
      bypass = Bypass.open()
      id = :"exseq_test_#{System.unique_integer([:positive])}"
      on_exit(fn -> :logger.remove_handler(id) end)
      {:ok, bypass: bypass, id: id, url: "http://localhost:#{bypass.port}/ingest/clef"}
    end

    defp add_handler(id, config) do
      :logger.add_handler(id, ExSeq, %{config: Map.merge(%{flush_interval: 3600}, config)})
    end

    test "sends logged events to Seq", %{bypass: bypass, id: id, url: url} do
      test = self()
      marker = "#{id}"

      Bypass.expect(bypass, "POST", "/ingest/clef", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)

        for line <- String.split(body, "\n"),
            event = Jason.decode!(line),
            event["marker"] == marker,
            do: send(test, {:event, event})

        Plug.Conn.resp(conn, 201, "")
      end)

      assert :ok = add_handler(id, %{seq_url: url})

      ExUnit.CaptureLog.capture_log(fn ->
        require Logger
        Logger.warning("hello", marker: marker, user_id: 123)
        Logger.flush()
      end)

      assert_received {:event, %{"@m" => "hello", "@l" => "Warning", "user_id" => 123}}
    end

    test "rejects unknown options", %{id: id} do
      assert {:error, {:handler_not_added, {:invalid_options, [:url]}}} =
               add_handler(id, %{url: "http://seq"})
    end

    test "can be removed and added again", %{id: id, url: url} do
      assert :ok = add_handler(id, %{seq_url: url})
      [{flusher, _}] = Registry.lookup(ExSeq.Registry, id)

      assert :ok = :logger.remove_handler(id)
      refute Process.alive?(flusher)

      assert :ok = add_handler(id, %{seq_url: url})
      assert [{_, _}] = Registry.lookup(ExSeq.Registry, id)
    end
  end
end
