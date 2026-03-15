defmodule Compressr.Telemetry.EmitterTest do
  use ExUnit.Case, async: true

  alias Compressr.Telemetry
  alias Compressr.Telemetry.Emitter

  setup do
    test_pid = self()

    attach_handler = fn event_name ->
      handler_id = "emitter-test-#{Enum.join(event_name, "-")}-#{System.unique_integer()}"

      :telemetry.attach(
        handler_id,
        event_name,
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      handler_id
    end

    %{attach_handler: attach_handler}
  end

  describe "emit_events_in/2" do
    test "emits events_in with correct measurements and metadata", %{
      attach_handler: attach_handler
    } do
      id = attach_handler.(Telemetry.events_in())

      Emitter.emit_events_in("source-1", %{count: 100, bytes: 4096})

      assert_receive {:telemetry, [:compressr, :events, :in], %{count: 100, bytes: 4096},
                       %{source_id: "source-1"}}

      :telemetry.detach(id)
    end
  end

  describe "emit_events_out/2" do
    test "emits events_out with correct measurements and metadata", %{
      attach_handler: attach_handler
    } do
      id = attach_handler.(Telemetry.events_out())

      Emitter.emit_events_out("dest-1", %{count: 50, bytes: 2048})

      assert_receive {:telemetry, [:compressr, :events, :out], %{count: 50, bytes: 2048},
                       %{destination_id: "dest-1"}}

      :telemetry.detach(id)
    end
  end

  describe "emit_events_dropped/3" do
    test "emits events_dropped with correct measurements and metadata", %{
      attach_handler: attach_handler
    } do
      id = attach_handler.(Telemetry.events_dropped())

      Emitter.emit_events_dropped("dest-1", 5, :buffer_full)

      assert_receive {:telemetry, [:compressr, :events, :dropped], %{count: 5},
                       %{destination_id: "dest-1", reason: :buffer_full}}

      :telemetry.detach(id)
    end
  end

  describe "emit_pipeline_duration/2" do
    test "emits pipeline execution duration", %{attach_handler: attach_handler} do
      id = attach_handler.(Telemetry.pipeline_execute())

      Emitter.emit_pipeline_duration("pipeline-1", 12.5)

      assert_receive {:telemetry, [:compressr, :pipeline, :execute], %{duration_ms: 12.5},
                       %{pipeline_id: "pipeline-1"}}

      :telemetry.detach(id)
    end
  end

  describe "emit_pipeline_function_duration/3" do
    test "emits pipeline function execution duration", %{attach_handler: attach_handler} do
      id = attach_handler.(Telemetry.pipeline_function_execute())

      Emitter.emit_pipeline_function_duration("pipeline-1", MyModule, 3.2)

      assert_receive {:telemetry, [:compressr, :pipeline, :function, :execute],
                       %{duration_ms: 3.2},
                       %{pipeline_id: "pipeline-1", function_module: MyModule}}

      :telemetry.detach(id)
    end
  end

  describe "emit_buffer_depth/2" do
    test "emits buffer depth with correct measurements", %{attach_handler: attach_handler} do
      id = attach_handler.(Telemetry.buffer_depth())

      Emitter.emit_buffer_depth("dest-1", %{bytes: 1_000_000, events: 500})

      assert_receive {:telemetry, [:compressr, :buffer, :depth],
                       %{bytes: 1_000_000, events: 500}, %{destination_id: "dest-1"}}

      :telemetry.detach(id)
    end
  end

  describe "emit_buffer_capacity/2" do
    test "emits buffer capacity percentage", %{attach_handler: attach_handler} do
      id = attach_handler.(Telemetry.buffer_capacity_pct())

      Emitter.emit_buffer_capacity("dest-1", 75.5)

      assert_receive {:telemetry, [:compressr, :buffer, :capacity_pct], %{percentage: 75.5},
                       %{destination_id: "dest-1"}}

      :telemetry.detach(id)
    end
  end

  describe "emit_backpressure/2" do
    test "emits backpressure active indicator", %{attach_handler: attach_handler} do
      id = attach_handler.(Telemetry.backpressure_active())

      Emitter.emit_backpressure("dest-1", 1)

      assert_receive {:telemetry, [:compressr, :backpressure, :active], %{active: 1},
                       %{destination_id: "dest-1"}}

      :telemetry.detach(id)
    end

    test "emits backpressure inactive indicator", %{attach_handler: attach_handler} do
      id = attach_handler.(Telemetry.backpressure_active())

      Emitter.emit_backpressure("dest-1", 0)

      assert_receive {:telemetry, [:compressr, :backpressure, :active], %{active: 0},
                       %{destination_id: "dest-1"}}

      :telemetry.detach(id)
    end
  end

  describe "emit_cluster_peers/1" do
    test "emits cluster peer count", %{attach_handler: attach_handler} do
      id = attach_handler.(Telemetry.cluster_peers())

      Emitter.emit_cluster_peers(3)

      assert_receive {:telemetry, [:compressr, :cluster, :peers], %{count: 3},
                       %{node: _node}}

      :telemetry.detach(id)
    end
  end

  describe "emit_destination_flush/2" do
    test "emits destination flush metrics", %{attach_handler: attach_handler} do
      id = attach_handler.(Telemetry.destination_flush())

      Emitter.emit_destination_flush("dest-1", %{duration_ms: 150, bytes: 50_000, events: 200})

      assert_receive {:telemetry, [:compressr, :destination, :flush],
                       %{duration_ms: 150, bytes: 50_000, events: 200},
                       %{destination_id: "dest-1"}}

      :telemetry.detach(id)
    end
  end

  describe "emit_source_connection/2" do
    test "emits source connection metrics", %{attach_handler: attach_handler} do
      id = attach_handler.(Telemetry.source_connection())

      measurements = %{active: 5, opened: 10, closed: 4, rejected: 1}
      Emitter.emit_source_connection("source-1", measurements)

      assert_receive {:telemetry, [:compressr, :source, :connection],
                       %{active: 5, opened: 10, closed: 4, rejected: 1},
                       %{source_id: "source-1"}}

      :telemetry.detach(id)
    end
  end

  describe "emit_schema_drift/3" do
    test "emits schema drift event", %{attach_handler: attach_handler} do
      id = attach_handler.(Telemetry.schema_drift())

      Emitter.emit_schema_drift("source-1", 2, :field_added)

      assert_receive {:telemetry, [:compressr, :schema, :drift], %{count: 2},
                       %{source_id: "source-1", drift_type: :field_added}}

      :telemetry.detach(id)
    end
  end
end
