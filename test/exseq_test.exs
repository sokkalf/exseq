defmodule ExSeqTest do
  use ExUnit.Case, async: true

  alias ExSeq.CLEFEvent

  @time 1_735_787_045_123_456

  describe "create_event/4" do
    test "builds an event from a log message" do
      event =
        ExSeq.create_event(:info, ["hello", ?\s, "world"], nil, time: @time, foo: "bar")

      assert %CLEFEvent{
               level: :Information,
               message: "hello world",
               exception: nil,
               timestamp: ~U[2025-01-02 03:04:05.123456Z]
             } = event

      assert event.properties == [foo: "bar"]
    end

    test "uses the original level from :erl_level" do
      assert %CLEFEvent{level: :Fatal} =
               ExSeq.create_event(:error, "hi", nil, time: @time, erl_level: :critical)

      assert %CLEFEvent{level: :Information} =
               ExSeq.create_event(:info, "hi", nil, time: @time, erl_level: :notice)
    end

    test "removes internal metadata" do
      event =
        ExSeq.create_event(:info, "hi", nil,
          time: @time,
          gl: self(),
          domain: [:elixir],
          erl_level: :info,
          foo: "bar"
        )

      assert event.properties == [foo: "bar"]
    end
  end

  test "can be installed more than once" do
    assert {:ok, %ExSeq{flusher: ExSeq.Flusher}} = ExSeq.init(ExSeq)
    assert {:ok, %ExSeq{flusher: ExSeq.Flusher}} = ExSeq.init(ExSeq)

    assert [{ExSeq.Flusher, pid, :worker, _}] = Supervisor.which_children(ExSeq.Supervisor)
    assert pid == Process.whereis(ExSeq.Flusher)
  end

  describe "handle_event/2" do
    defp log(level, min_level) do
      event = {level, Process.group_leader(), {Logger, "msg", nil, [time: @time]}}
      ExSeq.handle_event(event, %ExSeq{level: min_level, flusher: self()})
    end

    test "sends events at or above the configured level" do
      log(:warn, :info)
      assert_receive {:"$gen_cast", {:receive, %CLEFEvent{level: :Warning}}}

      log(:info, :info)
      assert_receive {:"$gen_cast", {:receive, %CLEFEvent{level: :Information}}}
    end

    test "accepts both :warn and :warning as the configured level" do
      for min_level <- [:warn, :warning] do
        log(:warn, min_level)
        assert_receive {:"$gen_cast", {:receive, %CLEFEvent{level: :Warning}}}

        log(:info, min_level)
        refute_receive {:"$gen_cast", _}
      end
    end

    test "drops events below the configured level" do
      log(:debug, :info)
      refute_receive {:"$gen_cast", _}
    end
  end
end
