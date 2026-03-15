defmodule Compressr.Pipeline do
  @moduledoc """
  Pipeline struct and execution engine.

  A pipeline consists of an ordered list of functions that are executed
  sequentially on each event. Each function may have a filter expression
  that determines whether it processes a given event, and a Final toggle
  that stops downstream processing when the function matches and executes.
  """

  alias Compressr.Pipeline.Function, as: PipelineFunction

  defstruct [
    :id,
    :name,
    functions: [],
    enabled: true,
    async_timeout: 30_000
  ]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          name: String.t() | nil,
          functions: [PipelineFunction.t()],
          enabled: boolean(),
          async_timeout: non_neg_integer()
        }

  @doc """
  Executes a pipeline against an event.

  Runs each function in order. Functions that are disabled are skipped.
  If a function has a filter and the event does not match, the event passes
  through unchanged. If a function has the Final toggle set and processes
  the event, no downstream functions are executed.

  Returns:
  - `{:ok, event}` — the event after all applicable functions have run
  - `{:drop, reason}` — the event was dropped by a function
  - `{:error, reason}` — an error occurred during execution
  """
  @spec execute(t(), map()) :: {:ok, map()} | {:drop, String.t()} | {:error, String.t()}
  def execute(%__MODULE__{enabled: false}, event) do
    {:ok, event}
  end

  def execute(%__MODULE__{functions: functions}, event) do
    execute_functions(functions, event)
  end

  defp execute_functions([], event), do: {:ok, event}

  defp execute_functions([%PipelineFunction{enabled: false} | rest], event) do
    execute_functions(rest, event)
  end

  defp execute_functions([func | rest], event) do
    if filter_matches?(func.filter, event) do
      case func.module.execute(event, func.config || %{}) do
        {:ok, updated_event} ->
          if func.final do
            {:ok, updated_event}
          else
            execute_functions(rest, updated_event)
          end

        {:drop, reason} ->
          {:drop, reason}

        {:error, reason} ->
          {:error, reason}
      end
    else
      execute_functions(rest, event)
    end
  end

  defp filter_matches?(nil, _event), do: true
  defp filter_matches?(filter, event) when is_function(filter, 1), do: filter.(event)
end
