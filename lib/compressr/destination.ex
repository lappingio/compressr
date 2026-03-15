defmodule Compressr.Destination do
  @moduledoc """
  Behaviour for destination implementations.

  All destination types must implement these callbacks to handle
  initialization, event delivery, flushing, stopping, and health reporting.
  """

  @doc """
  Initialize the destination with the given configuration map.
  Returns `{:ok, state}` on success or `{:error, reason}` on failure.
  """
  @callback init(config :: map()) :: {:ok, state :: term()} | {:error, reason :: term()}

  @doc """
  Send a batch of events to the destination.
  Returns `{:ok, new_state}` on success or `{:error, reason, state}` on failure.
  """
  @callback send_batch(events :: [map()], state :: term()) ::
              {:ok, state :: term()} | {:error, reason :: term(), state :: term()}

  @doc """
  Flush any buffered data in the destination.
  """
  @callback flush(state :: term()) :: {:ok, state :: term()}

  @doc """
  Stop the destination gracefully, flushing any remaining data.
  """
  @callback stop(state :: term()) :: :ok

  @doc """
  Report whether the destination is healthy.
  """
  @callback healthy?(state :: term()) :: boolean()
end
