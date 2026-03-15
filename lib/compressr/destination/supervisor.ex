defmodule Compressr.Destination.Supervisor do
  @moduledoc """
  DynamicSupervisor for destination worker processes.

  Manages the lifecycle of destination processes, allowing them to be
  started and stopped dynamically based on configuration changes.
  """

  use DynamicSupervisor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Start a destination process under this supervisor.

  Expects a destination config struct with at minimum `:id` and `:type` fields.
  """
  @spec start_destination(Compressr.Destination.Config.t()) :: DynamicSupervisor.on_start_child()
  def start_destination(%Compressr.Destination.Config{} = config) do
    module = destination_module(config.type)

    child_spec = %{
      id: {:destination, config.id},
      start: {Compressr.Destination.Worker, :start_link, [{module, config}]},
      restart: :transient
    }

    DynamicSupervisor.start_child(__MODULE__, child_spec)
  end

  @doc """
  Stop a running destination process by its ID.
  """
  @spec stop_destination(String.t()) :: :ok | {:error, :not_found}
  def stop_destination(destination_id) do
    case find_child(destination_id) do
      {:ok, pid} ->
        DynamicSupervisor.terminate_child(__MODULE__, pid)

      :error ->
        {:error, :not_found}
    end
  end

  defp find_child(destination_id) do
    children = DynamicSupervisor.which_children(__MODULE__)

    case Enum.find(children, fn {_id, pid, _type, _modules} ->
           is_pid(pid) and Compressr.Destination.Worker.destination_id(pid) == destination_id
         end) do
      {_id, pid, _type, _modules} -> {:ok, pid}
      nil -> :error
    end
  end

  defp destination_module("s3"), do: Compressr.Destination.S3
  defp destination_module("devnull"), do: Compressr.Destination.DevNull
  defp destination_module(type), do: raise("Unknown destination type: #{type}")
end
