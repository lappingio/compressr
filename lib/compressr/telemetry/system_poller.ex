defmodule Compressr.Telemetry.SystemPoller do
  @moduledoc """
  Periodic system metrics poller for BEAM VM stats.

  A GenServer that polls BEAM VM statistics every N seconds and emits
  telemetry events. Covers scheduler utilization, process count, memory
  breakdown, and run queue length.

  ## Configuration

    - `:interval_ms` - Polling interval in milliseconds. Defaults to 10_000 (10 seconds).

  ## Usage

  Add to your supervision tree:

      {Compressr.Telemetry.SystemPoller, interval_ms: 10_000}

  Or start directly:

      Compressr.Telemetry.SystemPoller.start_link(interval_ms: 5_000)
  """

  use GenServer

  @default_interval_ms 10_000

  def start_link(opts \\ []) do
    {gen_opts, config} = Keyword.split(opts, [:name])
    name = Keyword.get(gen_opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, config, name: name)
  end

  @impl true
  def init(opts) do
    interval_ms = Keyword.get(opts, :interval_ms, @default_interval_ms)

    # Enable scheduler wall time for utilization calculation
    :erlang.system_flag(:scheduler_wall_time, true)

    # Take initial sample for scheduler utilization delta
    initial_sample = :scheduler.sample()

    schedule_poll(interval_ms)

    {:ok, %{interval_ms: interval_ms, last_scheduler_sample: initial_sample}}
  end

  @impl true
  def handle_info(:poll, state) do
    current_sample = :scheduler.sample()

    utilization =
      :scheduler.utilization(state.last_scheduler_sample, current_sample)
      |> extract_total_utilization()

    measurements = collect_measurements(utilization)
    metadata = %{node: node()}

    :telemetry.execute(Compressr.Telemetry.system_metrics(), measurements, metadata)

    schedule_poll(state.interval_ms)

    {:noreply, %{state | last_scheduler_sample: current_sample}}
  end

  defp schedule_poll(interval_ms) do
    Process.send_after(self(), :poll, interval_ms)
  end

  defp collect_measurements(scheduler_utilization) do
    memory = :erlang.memory()

    %{
      scheduler_utilization: scheduler_utilization,
      process_count: :erlang.system_info(:process_count),
      memory_total: Keyword.get(memory, :total, 0),
      memory_processes: Keyword.get(memory, :processes, 0),
      memory_binary: Keyword.get(memory, :binary, 0),
      memory_ets: Keyword.get(memory, :ets, 0),
      memory_atom: Keyword.get(memory, :atom, 0),
      run_queue_length: get_run_queue_length()
    }
  end

  defp extract_total_utilization(utilization_data) do
    case List.keyfind(utilization_data, :total, 0) do
      {:total, total, _} -> total
      _ -> 0.0
    end
  end

  defp get_run_queue_length do
    case :erlang.statistics(:total_run_queue_lengths) do
      value when is_integer(value) -> value
      {total, _} -> total
    end
  end
end
