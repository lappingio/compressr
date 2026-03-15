defmodule Compressr.Telemetry do
  @moduledoc """
  Central telemetry definitions for the Compressr data pipeline.

  Defines all telemetry event names as module constants and documents the
  measurements and metadata for each event. These events use Elixir's built-in
  `:telemetry` library and can be bridged to any OTEL-compatible backend.

  ## Event Categories

  - **Throughput**: Events in/out/dropped counters
  - **Pipeline**: Execution duration for pipelines and functions
  - **Buffer**: Depth and capacity metrics
  - **Backpressure**: Active backpressure indicators
  - **Cluster**: Peer count and node information
  - **Destination**: Flush performance metrics
  - **Source**: Connection lifecycle metrics
  - **Schema**: Schema drift detection
  - **System**: BEAM VM metrics (emitted by SystemPoller)

  ## Event Definitions

  ### `[:compressr, :events, :in]`
  Measurements: `%{count: integer, bytes: integer}` | Metadata: `%{source_id: String.t()}`

  ### `[:compressr, :events, :out]`
  Measurements: `%{count: integer, bytes: integer}` | Metadata: `%{destination_id: String.t()}`

  ### `[:compressr, :events, :dropped]`
  Measurements: `%{count: integer}` | Metadata: `%{destination_id: String.t(), reason: atom}`

  ### `[:compressr, :pipeline, :execute]`
  Measurements: `%{duration_ms: number}` | Metadata: `%{pipeline_id: String.t()}`

  ### `[:compressr, :pipeline, :function, :execute]`
  Measurements: `%{duration_ms: number}` | Metadata: `%{pipeline_id: String.t(), function_module: module}`

  ### `[:compressr, :buffer, :depth]`
  Measurements: `%{bytes: integer, events: integer}` | Metadata: `%{destination_id: String.t()}`

  ### `[:compressr, :buffer, :capacity_pct]`
  Measurements: `%{percentage: number}` | Metadata: `%{destination_id: String.t()}`

  ### `[:compressr, :backpressure, :active]`
  Measurements: `%{active: 0 | 1}` | Metadata: `%{destination_id: String.t()}`

  ### `[:compressr, :cluster, :peers]`
  Measurements: `%{count: integer}` | Metadata: `%{node: atom}`

  ### `[:compressr, :destination, :flush]`
  Measurements: `%{duration_ms: number, bytes: integer, events: integer}` | Metadata: `%{destination_id: String.t()}`

  ### `[:compressr, :source, :connection]`
  Measurements: `%{active: integer, opened: integer, closed: integer, rejected: integer}` | Metadata: `%{source_id: String.t()}`

  ### `[:compressr, :schema, :drift]`
  Measurements: `%{count: integer}` | Metadata: `%{source_id: String.t(), drift_type: atom}`

  ### `[:compressr, :system, :metrics]`
  Measurements: `%{scheduler_utilization: float, process_count: integer, memory_total: integer, memory_processes: integer, memory_binary: integer, memory_ets: integer, memory_atom: integer, run_queue_length: integer}` | Metadata: `%{node: atom}`
  """

  # Throughput events
  @events_in [:compressr, :events, :in]
  @events_out [:compressr, :events, :out]
  @events_dropped [:compressr, :events, :dropped]

  # Pipeline events
  @pipeline_execute [:compressr, :pipeline, :execute]
  @pipeline_function_execute [:compressr, :pipeline, :function, :execute]

  # Buffer events
  @buffer_depth [:compressr, :buffer, :depth]
  @buffer_capacity_pct [:compressr, :buffer, :capacity_pct]

  # Backpressure events
  @backpressure_active [:compressr, :backpressure, :active]

  # Cluster events
  @cluster_peers [:compressr, :cluster, :peers]

  # Destination events
  @destination_flush [:compressr, :destination, :flush]

  # Source events
  @source_connection [:compressr, :source, :connection]

  # Schema events
  @schema_drift [:compressr, :schema, :drift]

  # System events (emitted by SystemPoller)
  @system_metrics [:compressr, :system, :metrics]

  # ── Public API ─────────────────────────────────────────────────────────

  @doc "Returns the event name for events received by a source."
  def events_in, do: @events_in

  @doc "Returns the event name for events sent to a destination."
  def events_out, do: @events_out

  @doc "Returns the event name for dropped events."
  def events_dropped, do: @events_dropped

  @doc "Returns the event name for pipeline execution."
  def pipeline_execute, do: @pipeline_execute

  @doc "Returns the event name for pipeline function execution."
  def pipeline_function_execute, do: @pipeline_function_execute

  @doc "Returns the event name for buffer depth."
  def buffer_depth, do: @buffer_depth

  @doc "Returns the event name for buffer capacity percentage."
  def buffer_capacity_pct, do: @buffer_capacity_pct

  @doc "Returns the event name for backpressure active indicator."
  def backpressure_active, do: @backpressure_active

  @doc "Returns the event name for cluster peer count."
  def cluster_peers, do: @cluster_peers

  @doc "Returns the event name for destination flush."
  def destination_flush, do: @destination_flush

  @doc "Returns the event name for source connections."
  def source_connection, do: @source_connection

  @doc "Returns the event name for schema drift."
  def schema_drift, do: @schema_drift

  @doc "Returns the event name for system metrics."
  def system_metrics, do: @system_metrics

  @doc """
  Returns a list of all defined telemetry event names.
  """
  def all_events do
    [
      @events_in,
      @events_out,
      @events_dropped,
      @pipeline_execute,
      @pipeline_function_execute,
      @buffer_depth,
      @buffer_capacity_pct,
      @backpressure_active,
      @cluster_peers,
      @destination_flush,
      @source_connection,
      @schema_drift,
      @system_metrics
    ]
  end
end
