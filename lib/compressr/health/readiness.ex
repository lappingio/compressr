defmodule Compressr.Health.Readiness do
  @moduledoc """
  GenServer that tracks subsystem readiness state.

  Subsystems register themselves as ready or not ready.
  The node is considered ready only when all registered subsystems are ready.
  """

  use GenServer

  # Client API

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Reports a subsystem as ready.
  """
  def report_ready(subsystem, name \\ __MODULE__) do
    GenServer.call(name, {:report_ready, subsystem})
  end

  @doc """
  Reports a subsystem as not ready.
  """
  def report_not_ready(subsystem, name \\ __MODULE__) do
    GenServer.call(name, {:report_not_ready, subsystem})
  end

  @doc """
  Returns the current readiness status of all subsystems.
  """
  def check(name \\ __MODULE__) do
    GenServer.call(name, :check)
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    {:ok, %{}}
  end

  @impl true
  def handle_call({:report_ready, subsystem}, _from, state) do
    {:reply, :ok, Map.put(state, subsystem, true)}
  end

  @impl true
  def handle_call({:report_not_ready, subsystem}, _from, state) do
    {:reply, :ok, Map.put(state, subsystem, false)}
  end

  @impl true
  def handle_call(:check, _from, state) do
    all_ready = state != %{} and Enum.all?(state, fn {_k, v} -> v end)

    status = if all_ready, do: :ready, else: :not_ready

    {:reply, %{status: status, subsystems: state}, state}
  end
end
