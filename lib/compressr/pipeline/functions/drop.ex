defmodule Compressr.Pipeline.Functions.Drop do
  @moduledoc """
  Drop function that removes events from the pipeline.

  When this function executes on an event (i.e., the event passes the
  pipeline-level filter), it drops the event, preventing it from reaching
  any downstream functions or the destination.

  Configuration:
  - No specific configuration needed. The filtering is handled at the
    pipeline function level via the filter expression.
  """

  @behaviour Compressr.Pipeline.Function

  @impl true
  def execute(_event, _config) do
    {:drop, "matched drop filter"}
  end
end
