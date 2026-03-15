defmodule Compressr.Pipeline.Functions.Comment do
  @moduledoc """
  Comment function — a no-op annotation for pipeline readability.

  This function does not modify the event in any way. It exists purely for
  documentation purposes within a pipeline configuration.

  Configuration:
  - `text` — the comment text (for display in pipeline configuration UIs)
  """

  @behaviour Compressr.Pipeline.Function

  @impl true
  def execute(event, _config) do
    {:ok, event}
  end
end
