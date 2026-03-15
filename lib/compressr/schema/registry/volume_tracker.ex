defmodule Compressr.Schema.Registry.VolumeTracker do
  @moduledoc """
  GenServer tracking per-log-type volume metrics within sources.

  Uses sliding window counters to compute events/sec and bytes/sec per
  log type per source. The default window is 60 seconds.
  """

  use GenServer

  @default_window_seconds 60

  # --- Public API ---

  @doc """
  Start the volume tracker.

  ## Options

    * `:name` - process name (defaults to `__MODULE__`)
    * `:window_seconds` - sliding window size in seconds (default 60)

  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    window_seconds = Keyword.get(opts, :window_seconds, @default_window_seconds)

    GenServer.start_link(__MODULE__, %{window_seconds: window_seconds}, name: name)
  end

  @doc """
  Record an event for a source/log_type pair.

  ## Parameters

    * `server` - the volume tracker pid or name
    * `source_id` - the source identifier
    * `log_type_id` - the log type identifier
    * `byte_size` - the size of the event in bytes

  """
  @spec record(GenServer.server(), String.t(), String.t(), non_neg_integer()) :: :ok
  def record(server \\ __MODULE__, source_id, log_type_id, byte_size) do
    GenServer.cast(server, {:record, source_id, log_type_id, byte_size})
  end

  @doc """
  Get volume breakdown for a source.

  Returns a map of `log_type_id => %{events_per_sec: float, bytes_per_sec: float, percentage: float}`.
  """
  @spec get_breakdown(GenServer.server(), String.t()) :: %{
          String.t() => %{
            events_per_sec: float(),
            bytes_per_sec: float(),
            percentage: float()
          }
        }
  def get_breakdown(server \\ __MODULE__, source_id) do
    GenServer.call(server, {:get_breakdown, source_id})
  end

  # --- GenServer Callbacks ---

  @impl true
  def init(%{window_seconds: window_seconds}) do
    # State: %{
    #   window_seconds: integer,
    #   entries: %{ {source_id, log_type_id} => [{timestamp_sec, byte_size}] }
    # }
    {:ok, %{window_seconds: window_seconds, entries: %{}}}
  end

  @impl true
  def handle_cast({:record, source_id, log_type_id, byte_size}, state) do
    now = System.monotonic_time(:second)
    key = {source_id, log_type_id}

    entries =
      Map.update(state.entries, key, [{now, byte_size}], fn existing ->
        [{now, byte_size} | existing]
      end)

    {:noreply, %{state | entries: entries}}
  end

  @impl true
  def handle_call({:get_breakdown, source_id}, _from, state) do
    now = System.monotonic_time(:second)
    cutoff = now - state.window_seconds

    # Find all log types for this source and compute metrics
    {source_metrics, updated_entries} =
      state.entries
      |> Enum.reduce({%{}, state.entries}, fn {{sid, log_type_id} = key, records}, {metrics, entries} ->
        if sid == source_id do
          # Prune old entries
          active = Enum.filter(records, fn {ts, _} -> ts > cutoff end)
          entries = Map.put(entries, key, active)

          event_count = length(active)
          total_bytes = Enum.reduce(active, 0, fn {_, bs}, acc -> acc + bs end)

          window = max(state.window_seconds, 1)
          events_per_sec = event_count / window
          bytes_per_sec = total_bytes / window

          metrics =
            Map.put(metrics, log_type_id, %{
              events_per_sec: events_per_sec,
              bytes_per_sec: bytes_per_sec,
              total_events: event_count
            })

          {metrics, entries}
        else
          {metrics, entries}
        end
      end)

    # Calculate percentages
    total_events =
      source_metrics
      |> Map.values()
      |> Enum.reduce(0, fn %{total_events: c}, acc -> acc + c end)

    breakdown =
      source_metrics
      |> Enum.map(fn {log_type_id, info} ->
        pct =
          if total_events > 0 do
            Float.round(info.total_events / total_events * 100.0, 1)
          else
            0.0
          end

        {log_type_id, %{
          events_per_sec: Float.round(info.events_per_sec, 4),
          bytes_per_sec: Float.round(info.bytes_per_sec, 4),
          percentage: pct
        }}
      end)
      |> Map.new()

    {:reply, breakdown, %{state | entries: updated_entries}}
  end
end
