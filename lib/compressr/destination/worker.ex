defmodule Compressr.Destination.Worker do
  @moduledoc """
  GenServer wrapper for destination implementations.

  Each destination process wraps a module implementing the `Compressr.Destination`
  behaviour and manages its lifecycle.
  """

  use GenServer

  defstruct [:module, :destination_id, :state, :config]

  def start_link({module, %Compressr.Destination.Config{} = config}) do
    GenServer.start_link(__MODULE__, {module, config})
  end

  @doc """
  Get the destination ID for a running worker process.
  """
  def destination_id(pid) do
    GenServer.call(pid, :destination_id)
  end

  @impl true
  def init({module, config}) do
    case module.init(config.config || %{}) do
      {:ok, dest_state} ->
        worker_state = %__MODULE__{
          module: module,
          destination_id: config.id,
          state: dest_state,
          config: config
        }

        {:ok, worker_state}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_call(:destination_id, _from, state) do
    {:reply, state.destination_id, state}
  end

  @impl true
  def handle_call({:send_batch, events}, _from, state) do
    case state.module.send_batch(events, state.state) do
      {:ok, new_dest_state} ->
        {:reply, :ok, %{state | state: new_dest_state}}

      {:error, reason, new_dest_state} ->
        {:reply, {:error, reason}, %{state | state: new_dest_state}}
    end
  end

  @impl true
  def handle_call(:flush, _from, state) do
    case state.module.flush(state.state) do
      {:ok, new_dest_state} ->
        {:reply, :ok, %{state | state: new_dest_state}}
    end
  end

  @impl true
  def terminate(_reason, state) do
    state.module.stop(state.state)
  end
end
