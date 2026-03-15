defmodule Compressr.Cost.Tracker do
  @moduledoc """
  GenServer that tracks usage metrics for cost estimation.

  Tracks counters per resource (source_id, destination_id, pipeline_id):
  - s3_bytes_written, s3_put_count, s3_get_count
  - glacier_restore_bytes (per tier: bulk, standard, expedited)
  - cross_az_bytes
  - dynamo_rcu, dynamo_wcu

  Counters can be reset on a configurable interval.
  """

  use GenServer

  @valid_metrics [
    :s3_bytes_written,
    :s3_put_count,
    :s3_get_count,
    :glacier_restore_bytes_bulk,
    :glacier_restore_bytes_standard,
    :glacier_restore_bytes_expedited,
    :cross_az_bytes,
    :dynamo_rcu,
    :dynamo_wcu
  ]

  @default_reset_interval :monthly

  # Client API

  @doc """
  Starts the tracker GenServer.

  ## Options

    * `:name` - Process name (default: `__MODULE__`)
    * `:reset_interval` - `:daily` or `:monthly` (default: `:monthly`)
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    reset_interval = Keyword.get(opts, :reset_interval, @default_reset_interval)
    GenServer.start_link(__MODULE__, %{reset_interval: reset_interval}, name: name)
  end

  @doc """
  Records a usage metric for a resource.

  ## Examples

      iex> Compressr.Cost.Tracker.record(:s3_put_count, "dest-1", 1)
      :ok

      iex> Compressr.Cost.Tracker.record(:s3_bytes_written, "dest-1", 1024)
      :ok
  """
  def record(metric, resource_id, amount, name \\ __MODULE__)
      when metric in @valid_metrics and is_number(amount) do
    GenServer.cast(name, {:record, metric, resource_id, amount})
  end

  @doc """
  Returns all counters for a specific resource.
  """
  def get_usage(resource_id, name \\ __MODULE__) do
    GenServer.call(name, {:get_usage, resource_id})
  end

  @doc """
  Returns all counters for all resources.
  """
  def get_all_usage(name \\ __MODULE__) do
    GenServer.call(name, :get_all_usage)
  end

  @doc """
  Resets all counters to zero.
  """
  def reset(name \\ __MODULE__) do
    GenServer.call(name, :reset)
  end

  @doc """
  Returns the list of valid metric names.
  """
  def valid_metrics, do: @valid_metrics

  # Server callbacks

  @impl true
  def init(%{reset_interval: reset_interval}) do
    state = %{
      counters: %{},
      reset_interval: reset_interval,
      last_reset: DateTime.utc_now()
    }

    schedule_reset(reset_interval)
    {:ok, state}
  end

  @impl true
  def handle_cast({:record, metric, resource_id, amount}, state) do
    counters =
      state.counters
      |> Map.update(resource_id, %{metric => amount}, fn resource_counters ->
        Map.update(resource_counters, metric, amount, &(&1 + amount))
      end)

    {:noreply, %{state | counters: counters}}
  end

  @impl true
  def handle_call({:get_usage, resource_id}, _from, state) do
    usage = Map.get(state.counters, resource_id, %{})
    {:reply, usage, state}
  end

  @impl true
  def handle_call(:get_all_usage, _from, state) do
    {:reply, state.counters, state}
  end

  @impl true
  def handle_call(:reset, _from, state) do
    {:reply, :ok, %{state | counters: %{}, last_reset: DateTime.utc_now()}}
  end

  @impl true
  def handle_info(:scheduled_reset, state) do
    schedule_reset(state.reset_interval)
    {:noreply, %{state | counters: %{}, last_reset: DateTime.utc_now()}}
  end

  defp schedule_reset(:daily) do
    # 24 hours in milliseconds
    Process.send_after(self(), :scheduled_reset, 24 * 60 * 60 * 1000)
  end

  defp schedule_reset(:monthly) do
    # Approximate 30 days in milliseconds
    Process.send_after(self(), :scheduled_reset, 30 * 24 * 60 * 60 * 1000)
  end

  defp schedule_reset(_), do: :ok
end
