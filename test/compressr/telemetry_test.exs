defmodule Compressr.TelemetryTest do
  use ExUnit.Case, async: true

  alias Compressr.Telemetry

  describe "event definitions" do
    test "all event names are defined as lists of atoms" do
      for event <- Telemetry.all_events() do
        assert is_list(event), "Event #{inspect(event)} should be a list"

        for segment <- event do
          assert is_atom(segment), "Event segment #{inspect(segment)} should be an atom"
        end
      end
    end

    test "all events start with :compressr" do
      for event <- Telemetry.all_events() do
        assert hd(event) == :compressr,
               "Event #{inspect(event)} should start with :compressr"
      end
    end

    test "all_events returns the expected number of events" do
      assert length(Telemetry.all_events()) == 13
    end

    test "individual event accessors return correct names" do
      assert Telemetry.events_in() == [:compressr, :events, :in]
      assert Telemetry.events_out() == [:compressr, :events, :out]
      assert Telemetry.events_dropped() == [:compressr, :events, :dropped]
      assert Telemetry.pipeline_execute() == [:compressr, :pipeline, :execute]

      assert Telemetry.pipeline_function_execute() == [
               :compressr,
               :pipeline,
               :function,
               :execute
             ]

      assert Telemetry.buffer_depth() == [:compressr, :buffer, :depth]
      assert Telemetry.buffer_capacity_pct() == [:compressr, :buffer, :capacity_pct]
      assert Telemetry.backpressure_active() == [:compressr, :backpressure, :active]
      assert Telemetry.cluster_peers() == [:compressr, :cluster, :peers]
      assert Telemetry.destination_flush() == [:compressr, :destination, :flush]
      assert Telemetry.source_connection() == [:compressr, :source, :connection]
      assert Telemetry.schema_drift() == [:compressr, :schema, :drift]
      assert Telemetry.system_metrics() == [:compressr, :system, :metrics]
    end
  end

  describe "event emission and handling" do
    test "events can be emitted and received by handlers" do
      test_pid = self()
      handler_id = "test-handler-#{System.unique_integer()}"

      :telemetry.attach(
        handler_id,
        Telemetry.events_in(),
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      :telemetry.execute(
        Telemetry.events_in(),
        %{count: 42, bytes: 1024},
        %{source_id: "test-source"}
      )

      assert_receive {:telemetry_event, [:compressr, :events, :in], %{count: 42, bytes: 1024},
                       %{source_id: "test-source"}}

      :telemetry.detach(handler_id)
    end

    test "all events can be emitted without error" do
      test_pid = self()
      handler_ids =
        for event <- Telemetry.all_events() do
          handler_id = "test-all-#{Enum.join(event, "-")}-#{System.unique_integer()}"

          :telemetry.attach(
            handler_id,
            event,
            fn event, _measurements, _metadata, _config ->
              send(test_pid, {:received, event})
            end,
            nil
          )

          handler_id
        end

      # Emit each event with minimal measurements
      :telemetry.execute(Telemetry.events_in(), %{count: 1, bytes: 1}, %{source_id: "s1"})
      :telemetry.execute(Telemetry.events_out(), %{count: 1, bytes: 1}, %{destination_id: "d1"})

      :telemetry.execute(Telemetry.events_dropped(), %{count: 1}, %{
        destination_id: "d1",
        reason: :overflow
      })

      :telemetry.execute(Telemetry.pipeline_execute(), %{duration_ms: 1}, %{pipeline_id: "p1"})

      :telemetry.execute(Telemetry.pipeline_function_execute(), %{duration_ms: 1}, %{
        pipeline_id: "p1",
        function_module: MyModule
      })

      :telemetry.execute(Telemetry.buffer_depth(), %{bytes: 1, events: 1}, %{
        destination_id: "d1"
      })

      :telemetry.execute(Telemetry.buffer_capacity_pct(), %{percentage: 50.0}, %{
        destination_id: "d1"
      })

      :telemetry.execute(Telemetry.backpressure_active(), %{active: 1}, %{
        destination_id: "d1"
      })

      :telemetry.execute(Telemetry.cluster_peers(), %{count: 3}, %{node: node()})

      :telemetry.execute(Telemetry.destination_flush(), %{duration_ms: 10, bytes: 100, events: 5},
        %{destination_id: "d1"}
      )

      :telemetry.execute(Telemetry.source_connection(), %{active: 1, opened: 1, closed: 0, rejected: 0},
        %{source_id: "s1"}
      )

      :telemetry.execute(Telemetry.schema_drift(), %{count: 1}, %{
        source_id: "s1",
        drift_type: :field_added
      })

      :telemetry.execute(Telemetry.system_metrics(), %{scheduler_utilization: 0.5, process_count: 100,
        memory_total: 1_000_000, memory_processes: 500_000, memory_binary: 200_000,
        memory_ets: 100_000, memory_atom: 50_000, run_queue_length: 0}, %{node: node()})

      for event <- Telemetry.all_events() do
        assert_receive {:received, ^event}
      end

      for handler_id <- handler_ids do
        :telemetry.detach(handler_id)
      end
    end
  end
end
