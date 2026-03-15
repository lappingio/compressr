defmodule Compressr.Source.Supervisor do
  @moduledoc """
  DynamicSupervisor for managing source processes.

  On application start, loads enabled source configurations from DynamoDB
  and starts their processes.
  """

  use DynamicSupervisor

  require Logger

  def start_link(opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Load and start all enabled sources from DynamoDB.

  Called after the supervisor is started, typically from the application
  supervision tree via a Task.
  """
  def load_sources do
    {:ok, configs} = Compressr.Source.Config.list()

    configs
    |> Enum.filter(fn config -> config["enabled"] == true end)
    |> Enum.each(fn config ->
      case start_source(config) do
        {:ok, _pid} ->
          Logger.info("Started source #{config["id"]} (#{config["type"]})")

        {:error, reason} ->
          Logger.error(
            "Failed to start source #{config["id"]}: #{inspect(reason)}"
          )
      end
    end)
  end

  @doc """
  Start a source process from its configuration.
  """
  @spec start_source(map()) :: {:ok, pid()} | {:error, term()}
  def start_source(config) when is_map(config) do
    source_id = config["id"]
    type = config["type"]

    case Compressr.Source.module_for_type(type) do
      {:ok, mod} ->
        child_spec = %{
          id: source_id,
          start: {Compressr.Source.Worker, :start_link, [{mod, config}]},
          restart: :transient
        }

        DynamicSupervisor.start_child(__MODULE__, child_spec)

      {:error, _} = err ->
        err
    end
  end

  @doc """
  Stop a source process by its ID.
  """
  @spec stop_source(String.t()) :: :ok | {:error, :not_found}
  def stop_source(source_id) do
    case find_child(source_id) do
      {:ok, pid} ->
        DynamicSupervisor.terminate_child(__MODULE__, pid)

      :error ->
        {:error, :not_found}
    end
  end

  @doc """
  Restart a source process with updated configuration.
  """
  @spec restart_source(map()) :: {:ok, pid()} | {:error, term()}
  def restart_source(config) do
    _ = stop_source(config["id"])
    start_source(config)
  end

  defp find_child(source_id) do
    children = DynamicSupervisor.which_children(__MODULE__)

    case Enum.find(children, fn {id, _pid, _type, _mods} -> id == source_id end) do
      {_, pid, _, _} when is_pid(pid) -> {:ok, pid}
      _ -> :error
    end
  end
end
