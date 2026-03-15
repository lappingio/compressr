defmodule Compressr.Telemetry.Metrics do
  @moduledoc """
  Telemetry.Metrics definitions for Compressr dashboards and reporters.

  Defines counter, sum, last_value, and distribution metrics for all
  Compressr telemetry events. These metric specs can be consumed by any
  Telemetry.Metrics-compatible reporter (Prometheus, StatsD, console, etc.).

  ## Usage

      # All metrics
      Compressr.Telemetry.Metrics.all()

      # By category
      Compressr.Telemetry.Metrics.throughput()
      Compressr.Telemetry.Metrics.pipeline()
      Compressr.Telemetry.Metrics.buffer()
  """

  import Telemetry.Metrics

  @doc "Returns all metric definitions."
  def all do
    throughput() ++
      pipeline() ++
      buffer() ++
      cluster() ++
      source() ++
      destination() ++
      schema() ++
      system()
  end

  @doc "Throughput metrics: events and bytes in/out/dropped."
  def throughput do
    [
      counter("compressr.events.in.count",
        tags: [:source_id],
        description: "Total events received"
      ),
      sum("compressr.events.in.bytes",
        tags: [:source_id],
        description: "Total bytes received"
      ),
      counter("compressr.events.out.count",
        tags: [:destination_id],
        description: "Total events sent"
      ),
      sum("compressr.events.out.bytes",
        tags: [:destination_id],
        description: "Total bytes sent"
      ),
      counter("compressr.events.dropped.count",
        tags: [:destination_id, :reason],
        description: "Total events dropped"
      )
    ]
  end

  @doc "Pipeline metrics: execution duration for pipelines and functions."
  def pipeline do
    [
      distribution("compressr.pipeline.execute.duration_ms",
        tags: [:pipeline_id],
        description: "Pipeline execution duration in milliseconds",
        reporter_options: [buckets: [1, 5, 10, 25, 50, 100, 250, 500, 1000]]
      ),
      distribution("compressr.pipeline.function.execute.duration_ms",
        tags: [:pipeline_id, :function_module],
        description: "Pipeline function execution duration in milliseconds",
        reporter_options: [buckets: [0.1, 0.5, 1, 5, 10, 25, 50, 100]]
      )
    ]
  end

  @doc "Buffer metrics: depth and capacity."
  def buffer do
    [
      last_value("compressr.buffer.depth.bytes",
        tags: [:destination_id],
        description: "Current buffer size in bytes"
      ),
      last_value("compressr.buffer.depth.events",
        tags: [:destination_id],
        description: "Current buffer event count"
      ),
      last_value("compressr.buffer.capacity_pct.percentage",
        tags: [:destination_id],
        description: "Buffer capacity percentage (0-100)"
      ),
      last_value("compressr.backpressure.active.active",
        tags: [:destination_id],
        description: "Backpressure active indicator (0 or 1)"
      )
    ]
  end

  @doc "Cluster metrics: peer count."
  def cluster do
    [
      last_value("compressr.cluster.peers.count",
        tags: [:node],
        description: "Number of peers in the cluster"
      )
    ]
  end

  @doc "Source metrics: connection lifecycle."
  def source do
    [
      last_value("compressr.source.connection.active",
        tags: [:source_id],
        description: "Active source connections"
      ),
      sum("compressr.source.connection.opened",
        tags: [:source_id],
        description: "Total connections opened"
      ),
      sum("compressr.source.connection.closed",
        tags: [:source_id],
        description: "Total connections closed"
      ),
      sum("compressr.source.connection.rejected",
        tags: [:source_id],
        description: "Total connections rejected"
      )
    ]
  end

  @doc "Destination metrics: flush performance."
  def destination do
    [
      distribution("compressr.destination.flush.duration_ms",
        tags: [:destination_id],
        description: "Destination flush duration in milliseconds",
        reporter_options: [buckets: [10, 50, 100, 250, 500, 1000, 2500, 5000]]
      ),
      sum("compressr.destination.flush.bytes",
        tags: [:destination_id],
        description: "Total bytes flushed"
      ),
      sum("compressr.destination.flush.events",
        tags: [:destination_id],
        description: "Total events flushed"
      )
    ]
  end

  @doc "Schema metrics: drift detection."
  def schema do
    [
      counter("compressr.schema.drift.count",
        tags: [:source_id, :drift_type],
        description: "Schema drift events detected"
      )
    ]
  end

  @doc "System metrics: BEAM VM stats."
  def system do
    [
      last_value("compressr.system.metrics.scheduler_utilization",
        tags: [:node],
        description: "BEAM scheduler utilization (0.0-1.0)"
      ),
      last_value("compressr.system.metrics.process_count",
        tags: [:node],
        description: "Number of BEAM processes"
      ),
      last_value("compressr.system.metrics.memory_total",
        tags: [:node],
        unit: :byte,
        description: "Total BEAM memory usage"
      ),
      last_value("compressr.system.metrics.memory_processes",
        tags: [:node],
        unit: :byte,
        description: "Memory used by processes"
      ),
      last_value("compressr.system.metrics.memory_binary",
        tags: [:node],
        unit: :byte,
        description: "Memory used by binaries"
      ),
      last_value("compressr.system.metrics.memory_ets",
        tags: [:node],
        unit: :byte,
        description: "Memory used by ETS tables"
      ),
      last_value("compressr.system.metrics.memory_atom",
        tags: [:node],
        unit: :byte,
        description: "Memory used by atoms"
      ),
      last_value("compressr.system.metrics.run_queue_length",
        tags: [:node],
        description: "BEAM run queue length"
      )
    ]
  end
end
