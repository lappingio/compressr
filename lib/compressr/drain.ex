defmodule Compressr.Drain do
  @moduledoc """
  Drain coordinator for graceful shutdown.

  When a SIGTERM is received, the drain coordinator orchestrates a graceful
  shutdown sequence:

  1. Mark node as not ready (Health.Readiness reports not_ready)
  2. Stop all source listeners (no new data accepted)
  3. Wait for in-flight events to finish processing
  4. Flush all destination buffers
  5. Leave the cluster gracefully
  6. Return :ok
  """

  use GenServer

  require Logger

  @default_drain_timeout 30_000

  # Client API

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Initiate graceful drain. Blocks until drain completes or times out.
  """
  @spec initiate(GenServer.server()) :: :ok | {:error, :timeout}
  def initiate(name \\ __MODULE__) do
    timeout = drain_timeout() + 5_000
    GenServer.call(name, :initiate_drain, timeout)
  end

  @doc """
  Returns true if a drain is currently in progress.
  """
  @spec draining?(GenServer.server()) :: boolean()
  def draining?(name \\ __MODULE__) do
    GenServer.call(name, :draining?)
  end

  # Server callbacks

  @impl true
  def init(opts) do
    state = %{
      draining: false,
      drain_timeout: Keyword.get(opts, :drain_timeout, drain_timeout()),
      readiness_server: Keyword.get(opts, :readiness_server, Compressr.Health.Readiness),
      steps_completed: []
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:initiate_drain, _from, %{draining: true} = state) do
    Logger.info("Drain already in progress, skipping duplicate initiate")
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:initiate_drain, _from, state) do
    Logger.info("Initiating graceful drain sequence")
    state = %{state | draining: true, steps_completed: []}

    result = execute_drain_steps(state)

    final_state = %{state | draining: false}
    {:reply, result, final_state}
  end

  @impl true
  def handle_call(:draining?, _from, state) do
    {:reply, state.draining, state}
  end

  # Private

  defp execute_drain_steps(state) do
    steps = [
      {:mark_not_ready, &mark_not_ready/1},
      {:stop_sources, &stop_sources/1},
      {:wait_in_flight, &wait_in_flight/1},
      {:flush_destinations, &flush_destinations/1},
      {:leave_cluster, &leave_cluster/1}
    ]

    Enum.reduce_while(steps, :ok, fn {step_name, step_fn}, _acc ->
      Logger.info("Drain step: #{step_name}")

      case step_fn.(state) do
        :ok ->
          Logger.info("Drain step completed: #{step_name}")
          {:cont, :ok}

        {:error, reason} ->
          Logger.error("Drain step failed: #{step_name} — #{inspect(reason)}")
          # Continue draining even if a step fails — best effort
          {:cont, :ok}
      end
    end)
  end

  defp mark_not_ready(state) do
    try do
      Compressr.Health.Readiness.report_not_ready(:drain, state.readiness_server)
      :ok
    rescue
      _ -> :ok
    catch
      _, _ -> :ok
    end
  end

  defp stop_sources(_state) do
    try do
      children = DynamicSupervisor.which_children(Compressr.Source.Supervisor)

      Enum.each(children, fn
        {_id, pid, _type, _mods} when is_pid(pid) ->
          DynamicSupervisor.terminate_child(Compressr.Source.Supervisor, pid)

        _ ->
          :ok
      end)

      :ok
    rescue
      _ -> :ok
    catch
      _, _ -> :ok
    end
  end

  defp wait_in_flight(state) do
    # Wait for in-flight events to finish processing.
    # In the current implementation, we use a simple sleep with the configured timeout.
    # This will be enhanced once pipeline processing tracking is implemented.
    timeout = min(state.drain_timeout, @default_drain_timeout)
    Logger.info("Waiting up to #{timeout}ms for in-flight events to complete")

    # Check if there are any active destination workers processing events
    try do
      children = DynamicSupervisor.which_children(Compressr.Destination.Supervisor)

      if Enum.empty?(children) do
        :ok
      else
        # Give a brief window for in-flight events to finish
        Process.sleep(min(timeout, 1_000))
        :ok
      end
    rescue
      _ -> :ok
    catch
      _, _ -> :ok
    end
  end

  defp flush_destinations(_state) do
    try do
      children = DynamicSupervisor.which_children(Compressr.Destination.Supervisor)

      Enum.each(children, fn
        {_id, pid, _type, _mods} when is_pid(pid) ->
          # Attempt graceful shutdown of each destination worker
          try do
            GenServer.stop(pid, :normal, 5_000)
          catch
            :exit, _ -> :ok
          end

        _ ->
          :ok
      end)

      :ok
    rescue
      _ -> :ok
    catch
      _, _ -> :ok
    end
  end

  defp leave_cluster(_state) do
    try do
      nodes = Node.list()

      if Enum.empty?(nodes) do
        Logger.debug("No cluster peers, skipping cluster leave")
      else
        Logger.info("Leaving cluster, disconnecting from #{length(nodes)} peers")

        Enum.each(nodes, fn node ->
          Node.disconnect(node)
        end)
      end

      :ok
    rescue
      _ -> :ok
    catch
      _, _ -> :ok
    end
  end

  defp drain_timeout do
    Application.get_env(:compressr, :drain_timeout, @default_drain_timeout)
  end
end
