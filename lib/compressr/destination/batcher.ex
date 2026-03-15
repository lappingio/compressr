defmodule Compressr.Destination.Batcher do
  @moduledoc """
  Generic batching GenServer that accumulates events and flushes
  based on configurable time interval, event count, or byte size.

  ## Options

    * `:destination_module` - Module implementing `Compressr.Destination` (required)
    * `:destination_state` - Initial state for the destination (required)
    * `:batch_size` - Max events before auto-flush (default: 1000)
    * `:batch_timeout_ms` - Max ms between flushes (default: 5000)
    * `:max_batch_bytes` - Max bytes before auto-flush (default: 5_242_880)
  """

  use GenServer

  defstruct [
    :destination_module,
    :destination_state,
    :batch_size,
    :batch_timeout_ms,
    :max_batch_bytes,
    :timer_ref,
    buffer: [],
    buffer_count: 0,
    buffer_bytes: 0
  ]

  # --- Client API ---

  def start_link(opts) do
    name = Keyword.get(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Add an event to the batcher. Triggers a flush if batch thresholds are met.
  """
  def add_event(batcher, event) do
    GenServer.call(batcher, {:add_event, event})
  end

  @doc """
  Manually flush all buffered events to the destination.
  """
  def flush(batcher) do
    GenServer.call(batcher, :flush)
  end

  @doc """
  Get the current state for inspection/testing.
  """
  def get_state(batcher) do
    GenServer.call(batcher, :get_state)
  end

  # --- Server callbacks ---

  @impl true
  def init(opts) do
    state = %__MODULE__{
      destination_module: Keyword.fetch!(opts, :destination_module),
      destination_state: Keyword.fetch!(opts, :destination_state),
      batch_size: Keyword.get(opts, :batch_size, 1000),
      batch_timeout_ms: Keyword.get(opts, :batch_timeout_ms, 5000),
      max_batch_bytes: Keyword.get(opts, :max_batch_bytes, 5_242_880),
      buffer: [],
      buffer_count: 0,
      buffer_bytes: 0
    }

    state = schedule_flush(state)
    {:ok, state}
  end

  @impl true
  def handle_call({:add_event, event}, _from, state) do
    event_bytes = estimate_bytes(event)

    new_state = %{
      state
      | buffer: [event | state.buffer],
        buffer_count: state.buffer_count + 1,
        buffer_bytes: state.buffer_bytes + event_bytes
    }

    if should_flush?(new_state) do
      {:ok, flushed_state} = do_flush(new_state)
      {:reply, :ok, flushed_state}
    else
      {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call(:flush, _from, state) do
    {:ok, new_state} = do_flush(state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_info(:flush_timeout, state) do
    {:ok, new_state} = do_flush(state)
    new_state = schedule_flush(new_state)
    {:noreply, new_state}
  end

  @impl true
  def terminate(_reason, state) do
    do_flush(state)
    :ok
  end

  # --- Internal ---

  defp should_flush?(state) do
    state.buffer_count >= state.batch_size or
      state.buffer_bytes >= state.max_batch_bytes
  end

  defp do_flush(%{buffer: []} = state), do: {:ok, state}

  defp do_flush(state) do
    events = Enum.reverse(state.buffer)

    case state.destination_module.send_batch(events, state.destination_state) do
      {:ok, new_dest_state} ->
        {:ok,
         %{
           state
           | destination_state: new_dest_state,
             buffer: [],
             buffer_count: 0,
             buffer_bytes: 0
         }}

      {:error, _reason, new_dest_state} ->
        # On error, clear the buffer to avoid infinite retry loops.
        # In production, a dead-letter queue or retry mechanism would handle this.
        {:ok,
         %{
           state
           | destination_state: new_dest_state,
             buffer: [],
             buffer_count: 0,
             buffer_bytes: 0
         }}
    end
  end

  defp schedule_flush(state) do
    if state.timer_ref, do: Process.cancel_timer(state.timer_ref)
    ref = Process.send_after(self(), :flush_timeout, state.batch_timeout_ms)
    %{state | timer_ref: ref}
  end

  defp estimate_bytes(event) when is_map(event) do
    case Jason.encode(event) do
      {:ok, json} -> byte_size(json)
      _ -> 100
    end
  end

  defp estimate_bytes(_), do: 100
end
