defmodule Compressr.Telemetry.MetricsTest do
  use ExUnit.Case, async: true

  alias Compressr.Telemetry.Metrics

  # Telemetry.Metrics stores name as a list of atoms, e.g. [:compressr, :events, :in, :count]
  defp name_to_string(name_atoms), do: Enum.join(name_atoms, ".")

  defp metric_names(metrics), do: Enum.map(metrics, &name_to_string(&1.name))

  describe "all/0" do
    test "returns a list of Telemetry.Metrics structs" do
      metrics = Metrics.all()
      assert is_list(metrics)
      assert length(metrics) > 0

      for metric <- metrics do
        assert is_struct(metric),
               "Expected a struct, got #{inspect(metric)}"

        assert metric.__struct__ in [
                 Telemetry.Metrics.Counter,
                 Telemetry.Metrics.Sum,
                 Telemetry.Metrics.LastValue,
                 Telemetry.Metrics.Distribution
               ],
               "Unexpected metric type: #{inspect(metric.__struct__)}"
      end
    end

    test "all metrics have descriptions" do
      for metric <- Metrics.all() do
        assert is_binary(metric.description),
               "Metric #{inspect(metric.name)} should have a description"

        assert String.length(metric.description) > 0,
               "Metric #{inspect(metric.name)} description should not be empty"
      end
    end
  end

  describe "category functions" do
    test "throughput metrics cover events in, out, and dropped" do
      names = metric_names(Metrics.throughput())

      assert "compressr.events.in.count" in names
      assert "compressr.events.in.bytes" in names
      assert "compressr.events.out.count" in names
      assert "compressr.events.out.bytes" in names
      assert "compressr.events.dropped.count" in names
    end

    test "pipeline metrics cover execution durations" do
      names = metric_names(Metrics.pipeline())

      assert "compressr.pipeline.execute.duration_ms" in names
      assert "compressr.pipeline.function.execute.duration_ms" in names
    end

    test "buffer metrics cover depth, capacity, and backpressure" do
      names = metric_names(Metrics.buffer())

      assert "compressr.buffer.depth.bytes" in names
      assert "compressr.buffer.depth.events" in names
      assert "compressr.buffer.capacity_pct.percentage" in names
      assert "compressr.backpressure.active.active" in names
    end

    test "cluster metrics cover peer count" do
      names = metric_names(Metrics.cluster())
      assert "compressr.cluster.peers.count" in names
    end

    test "source metrics cover connections" do
      names = metric_names(Metrics.source())

      assert "compressr.source.connection.active" in names
      assert "compressr.source.connection.opened" in names
      assert "compressr.source.connection.closed" in names
      assert "compressr.source.connection.rejected" in names
    end

    test "destination metrics cover flush performance" do
      names = metric_names(Metrics.destination())

      assert "compressr.destination.flush.duration_ms" in names
      assert "compressr.destination.flush.bytes" in names
      assert "compressr.destination.flush.events" in names
    end

    test "schema metrics cover drift detection" do
      names = metric_names(Metrics.schema())
      assert "compressr.schema.drift.count" in names
    end

    test "system metrics cover BEAM VM stats" do
      names = metric_names(Metrics.system())

      assert "compressr.system.metrics.scheduler_utilization" in names
      assert "compressr.system.metrics.process_count" in names
      assert "compressr.system.metrics.memory_total" in names
      assert "compressr.system.metrics.memory_processes" in names
      assert "compressr.system.metrics.memory_binary" in names
      assert "compressr.system.metrics.memory_ets" in names
      assert "compressr.system.metrics.memory_atom" in names
      assert "compressr.system.metrics.run_queue_length" in names
    end

    test "all categories combined equal all metrics" do
      all = Metrics.all()

      combined =
        Metrics.throughput() ++
          Metrics.pipeline() ++
          Metrics.buffer() ++
          Metrics.cluster() ++
          Metrics.source() ++
          Metrics.destination() ++
          Metrics.schema() ++
          Metrics.system()

      assert length(all) == length(combined)
      assert Enum.map(all, & &1.name) == Enum.map(combined, & &1.name)
    end
  end

  describe "metric types" do
    test "throughput events use counters and sums" do
      types = Metrics.throughput() |> Enum.map(& &1.__struct__) |> Enum.uniq()
      assert Telemetry.Metrics.Counter in types
      assert Telemetry.Metrics.Sum in types
    end

    test "pipeline durations use distributions" do
      for metric <- Metrics.pipeline() do
        assert metric.__struct__ == Telemetry.Metrics.Distribution
      end
    end

    test "buffer metrics use last_value" do
      for metric <- Metrics.buffer() do
        assert metric.__struct__ == Telemetry.Metrics.LastValue
      end
    end

    test "distribution metrics have buckets in reporter_options" do
      distributions =
        Metrics.all()
        |> Enum.filter(&(&1.__struct__ == Telemetry.Metrics.Distribution))

      for metric <- distributions do
        assert is_list(metric.reporter_options[:buckets]),
               "Distribution metric #{inspect(metric.name)} should have buckets in reporter_options"
      end
    end
  end
end
