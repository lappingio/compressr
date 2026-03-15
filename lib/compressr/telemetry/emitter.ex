defmodule Compressr.Telemetry.Emitter do
  @moduledoc """
  Helper module for emitting Compressr telemetry events.

  Provides thin wrappers around `:telemetry.execute/3` with correct event
  names and measurement/metadata validation. Use these helpers throughout
  the data path rather than calling `:telemetry.execute/3` directly.

  ## Examples

      Compressr.Telemetry.Emitter.emit_events_in("source-1", %{count: 100, bytes: 4096})
      Compressr.Telemetry.Emitter.emit_pipeline_duration("pipeline-1", 12.5)
  """

  alias Compressr.Telemetry

  @doc """
  Emit an events-in telemetry event.

  ## Parameters
    - `source_id` - The source identifier
    - `measurements` - Map with `:count` and `:bytes` keys
  """
  def emit_events_in(source_id, %{count: _count, bytes: _bytes} = measurements) do
    :telemetry.execute(Telemetry.events_in(), measurements, %{source_id: source_id})
  end

  @doc """
  Emit an events-out telemetry event.

  ## Parameters
    - `destination_id` - The destination identifier
    - `measurements` - Map with `:count` and `:bytes` keys
  """
  def emit_events_out(destination_id, %{count: _count, bytes: _bytes} = measurements) do
    :telemetry.execute(Telemetry.events_out(), measurements, %{destination_id: destination_id})
  end

  @doc """
  Emit an events-dropped telemetry event.

  ## Parameters
    - `destination_id` - The destination identifier
    - `count` - Number of events dropped
    - `reason` - Atom describing why events were dropped
  """
  def emit_events_dropped(destination_id, count, reason) when is_atom(reason) do
    :telemetry.execute(Telemetry.events_dropped(), %{count: count}, %{
      destination_id: destination_id,
      reason: reason
    })
  end

  @doc """
  Emit a pipeline execution duration event.

  ## Parameters
    - `pipeline_id` - The pipeline identifier
    - `duration_ms` - Execution duration in milliseconds
  """
  def emit_pipeline_duration(pipeline_id, duration_ms) do
    :telemetry.execute(Telemetry.pipeline_execute(), %{duration_ms: duration_ms}, %{
      pipeline_id: pipeline_id
    })
  end

  @doc """
  Emit a pipeline function execution duration event.

  ## Parameters
    - `pipeline_id` - The pipeline identifier
    - `function_module` - The module that implements the function
    - `duration_ms` - Execution duration in milliseconds
  """
  def emit_pipeline_function_duration(pipeline_id, function_module, duration_ms) do
    :telemetry.execute(Telemetry.pipeline_function_execute(), %{duration_ms: duration_ms}, %{
      pipeline_id: pipeline_id,
      function_module: function_module
    })
  end

  @doc """
  Emit a buffer depth event.

  ## Parameters
    - `destination_id` - The destination identifier
    - `measurements` - Map with `:bytes` and `:events` keys
  """
  def emit_buffer_depth(destination_id, %{bytes: _bytes, events: _events} = measurements) do
    :telemetry.execute(Telemetry.buffer_depth(), measurements, %{
      destination_id: destination_id
    })
  end

  @doc """
  Emit a buffer capacity percentage event.

  ## Parameters
    - `destination_id` - The destination identifier
    - `percentage` - Buffer fill percentage (0-100)
  """
  def emit_buffer_capacity(destination_id, percentage) do
    :telemetry.execute(Telemetry.buffer_capacity_pct(), %{percentage: percentage}, %{
      destination_id: destination_id
    })
  end

  @doc """
  Emit a backpressure active indicator event.

  ## Parameters
    - `destination_id` - The destination identifier
    - `active` - 1 if backpressure is active, 0 if not
  """
  def emit_backpressure(destination_id, active) when active in [0, 1] do
    :telemetry.execute(Telemetry.backpressure_active(), %{active: active}, %{
      destination_id: destination_id
    })
  end

  @doc """
  Emit a cluster peers count event.

  ## Parameters
    - `count` - Number of peers in the cluster
  """
  def emit_cluster_peers(count) do
    :telemetry.execute(Telemetry.cluster_peers(), %{count: count}, %{node: node()})
  end

  @doc """
  Emit a destination flush event.

  ## Parameters
    - `destination_id` - The destination identifier
    - `measurements` - Map with `:duration_ms`, `:bytes`, and `:events` keys
  """
  def emit_destination_flush(
        destination_id,
        %{duration_ms: _dur, bytes: _bytes, events: _events} = measurements
      ) do
    :telemetry.execute(Telemetry.destination_flush(), measurements, %{
      destination_id: destination_id
    })
  end

  @doc """
  Emit a source connection event.

  ## Parameters
    - `source_id` - The source identifier
    - `measurements` - Map with `:active`, `:opened`, `:closed`, `:rejected` keys
  """
  def emit_source_connection(source_id, measurements) do
    :telemetry.execute(Telemetry.source_connection(), measurements, %{source_id: source_id})
  end

  @doc """
  Emit a schema drift event.

  ## Parameters
    - `source_id` - The source identifier
    - `count` - Number of drift events
    - `drift_type` - Atom describing the type of drift
  """
  def emit_schema_drift(source_id, count, drift_type) when is_atom(drift_type) do
    :telemetry.execute(Telemetry.schema_drift(), %{count: count}, %{
      source_id: source_id,
      drift_type: drift_type
    })
  end
end
