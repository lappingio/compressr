defmodule Compressr.Pipeline.Function do
  @moduledoc """
  Behaviour for pipeline functions.

  All pipeline functions must implement this behaviour. Each function receives
  an event and a configuration map, and returns the transformed event, a drop
  signal, or an error.
  """

  @doc """
  Executes the function logic on an event.

  Returns:
  - `{:ok, event}` — the (possibly modified) event
  - `{:drop, reason}` — the event should be dropped from the pipeline
  - `{:error, reason}` — an error occurred during execution
  """
  @callback execute(event :: map(), config :: map()) ::
              {:ok, map()} | {:drop, String.t()} | {:error, String.t()}

  @doc """
  A function step within a pipeline, wrapping a module that implements the
  Function behaviour along with its configuration and pipeline options.
  """
  defstruct [
    :id,
    :module,
    :config,
    :description,
    filter: nil,
    final: false,
    enabled: true
  ]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          module: module(),
          config: map(),
          description: String.t() | nil,
          filter: (map() -> boolean()) | nil,
          final: boolean(),
          enabled: boolean()
        }
end
