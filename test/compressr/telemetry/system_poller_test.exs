defmodule Compressr.Telemetry.SystemPollerTest do
  use ExUnit.Case, async: true

  alias Compressr.Telemetry
  alias Compressr.Telemetry.SystemPoller

  describe "system poller" do
    test "emits system metrics on poll" do
      test_pid = self()
      handler_id = "system-poller-test-#{System.unique_integer()}"

      :telemetry.attach(
        handler_id,
        Telemetry.system_metrics(),
        fn _event, measurements, metadata, _config ->
          send(test_pid, {:system_metrics, measurements, metadata})
        end,
        nil
      )

      # Start poller with a very short interval
      {:ok, pid} =
        SystemPoller.start_link(
          interval_ms: 50,
          name: :"system_poller_test_#{System.unique_integer()}"
        )

      assert_receive {:system_metrics, measurements, metadata}, 5_000

      # Verify measurement keys exist and values are reasonable
      assert is_float(measurements.scheduler_utilization)
      assert measurements.scheduler_utilization >= 0.0
      assert measurements.scheduler_utilization <= 1.0

      assert is_integer(measurements.process_count)
      assert measurements.process_count > 0

      assert is_integer(measurements.memory_total)
      assert measurements.memory_total > 0

      assert is_integer(measurements.memory_processes)
      assert measurements.memory_processes > 0

      assert is_integer(measurements.memory_binary)
      assert measurements.memory_binary >= 0

      assert is_integer(measurements.memory_ets)
      assert measurements.memory_ets >= 0

      assert is_integer(measurements.memory_atom)
      assert measurements.memory_atom > 0

      assert is_integer(measurements.run_queue_length)
      assert measurements.run_queue_length >= 0

      # Verify metadata
      assert metadata.node == node()

      GenServer.stop(pid)
      :telemetry.detach(handler_id)
    end

    test "emits metrics periodically" do
      test_pid = self()
      handler_id = "system-poller-periodic-#{System.unique_integer()}"

      :telemetry.attach(
        handler_id,
        Telemetry.system_metrics(),
        fn _event, _measurements, _metadata, _config ->
          send(test_pid, :metric_emitted)
        end,
        nil
      )

      {:ok, pid} =
        SystemPoller.start_link(
          interval_ms: 50,
          name: :"system_poller_periodic_#{System.unique_integer()}"
        )

      # Should receive at least 2 metrics within 200ms
      assert_receive :metric_emitted, 5_000
      assert_receive :metric_emitted, 5_000

      GenServer.stop(pid)
      :telemetry.detach(handler_id)
    end
  end
end
