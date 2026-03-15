defmodule Compressr.Telemetry.ReporterTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Compressr.Telemetry
  alias Compressr.Telemetry.Reporter

  # Test logger level is :warning, so we log at :warning level to be captured
  @log_level :warning

  setup do
    on_exit(fn -> Reporter.detach() end)
    :ok
  end

  describe "attach/1" do
    test "attaches to all events by default" do
      assert :ok = Reporter.attach(level: @log_level)

      log =
        capture_log(fn ->
          :telemetry.execute(
            Telemetry.events_in(),
            %{count: 10, bytes: 512},
            %{source_id: "test-source"}
          )
        end)

      assert log =~ "compressr.events.in"
      assert log =~ "test-source"
    end

    test "attaches to specific events only" do
      assert :ok =
               Reporter.attach(events: [Telemetry.events_in()], level: @log_level)

      # Should log events_in
      log =
        capture_log(fn ->
          :telemetry.execute(
            Telemetry.events_in(),
            %{count: 1, bytes: 10},
            %{source_id: "s1"}
          )
        end)

      assert log =~ "compressr.events.in"

      # Should NOT log events_out (not attached)
      log =
        capture_log(fn ->
          :telemetry.execute(
            Telemetry.events_out(),
            %{count: 1, bytes: 10},
            %{destination_id: "d1"}
          )
        end)

      refute log =~ "compressr.events.out"
    end
  end

  describe "detach/0" do
    test "stops logging events after detach" do
      Reporter.attach(level: @log_level)

      log =
        capture_log(fn ->
          :telemetry.execute(
            Telemetry.events_in(),
            %{count: 1, bytes: 1},
            %{source_id: "s1"}
          )
        end)

      assert log =~ "compressr.events.in"

      Reporter.detach()

      log =
        capture_log(fn ->
          :telemetry.execute(
            Telemetry.events_in(),
            %{count: 1, bytes: 1},
            %{source_id: "s1"}
          )
        end)

      refute log =~ "compressr.events.in"
    end
  end

  describe "handle_event/4" do
    test "logs event as structured JSON" do
      Reporter.attach(level: @log_level)

      log =
        capture_log(fn ->
          :telemetry.execute(
            Telemetry.pipeline_execute(),
            %{duration_ms: 42.5},
            %{pipeline_id: "pipe-1"}
          )
        end)

      assert log =~ "compressr.pipeline.execute"
      assert log =~ "42.5"
      assert log =~ "pipe-1"
    end

    test "respects sample rate of 0.0 (no logging)" do
      Reporter.attach(sample_rate: 0.0, level: @log_level)

      log =
        capture_log(fn ->
          for _ <- 1..100 do
            :telemetry.execute(
              Telemetry.events_in(),
              %{count: 1, bytes: 1},
              %{source_id: "s1"}
            )
          end
        end)

      refute log =~ "compressr.events.in"
    end

    test "sample rate of 1.0 logs everything" do
      Reporter.attach(sample_rate: 1.0, level: @log_level)

      log =
        capture_log(fn ->
          :telemetry.execute(
            Telemetry.events_in(),
            %{count: 1, bytes: 1},
            %{source_id: "s1"}
          )
        end)

      assert log =~ "compressr.events.in"
    end
  end
end
