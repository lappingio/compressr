defmodule Compressr.Destination.DevNull do
  @moduledoc """
  DevNull destination that discards all events.

  Always succeeds, requires no configuration. Useful for testing
  and as a default discard destination.
  """

  @behaviour Compressr.Destination

  defstruct events_discarded: 0

  @impl true
  def init(_config) do
    {:ok, %__MODULE__{}}
  end

  @impl true
  def send_batch(events, %__MODULE__{} = state) do
    {:ok, %{state | events_discarded: state.events_discarded + length(events)}}
  end

  @impl true
  def flush(%__MODULE__{} = state) do
    {:ok, state}
  end

  @impl true
  def stop(%__MODULE__{}) do
    :ok
  end

  @impl true
  def healthy?(%__MODULE__{}), do: true
end
