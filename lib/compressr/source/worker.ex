defmodule Compressr.Source.Worker do
  @moduledoc """
  GenServer wrapper for source behaviour implementations.

  Manages the lifecycle of a single source, calling the behaviour's
  `init/1`, `handle_data/2`, and `stop/1` callbacks.
  """

  use GenServer

  require Logger

  def start_link({module, config}) do
    GenServer.start_link(__MODULE__, {module, config}, name: via(config["id"]))
  end

  @doc """
  Send data to a source worker for processing.

  Returns the list of events produced.
  """
  def send_data(source_id, data) do
    GenServer.call(via(source_id), {:handle_data, data})
  end

  @impl true
  def init({module, config}) do
    source_config = config["config"] || %{}

    case module.init(source_config) do
      {:ok, source_state} ->
        {:ok,
         %{
           module: module,
           config: config,
           source_state: source_state,
           source_id: config["id"]
         }}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_call({:handle_data, data}, _from, state) do
    case state.module.handle_data(data, state.source_state) do
      {:ok, events, new_source_state} ->
        # Tag events with source ID
        tagged_events =
          Enum.map(events, fn event ->
            Compressr.Event.put_internal(event, "__inputId", state.source_id)
          end)

        {:reply, {:ok, tagged_events}, %{state | source_state: new_source_state}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def terminate(_reason, state) do
    state.module.stop(state.source_state)
    :ok
  end

  defp via(source_id) do
    {:via, Registry, {Compressr.Source.Registry, source_id}}
  end
end
