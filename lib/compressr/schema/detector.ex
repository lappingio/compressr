defmodule Compressr.Schema.Detector do
  @moduledoc """
  Schema drift detection GenServer.

  One detector runs per source. It learns the schema from the first N events
  (configurable, default 1000), then compares each subsequent event's structure
  against the baseline.

  Uses a fingerprint (hash of sorted field names) for fast-path comparison.
  Only performs deep comparison when the fingerprint differs from the baseline.

  Detects: new fields, missing fields, type changes.
  """

  use GenServer

  require Logger

  alias Compressr.Schema.{Schema, DriftEvent, Alerter, Store}

  @default_learning_window 1000

  # --- Public API ---

  @doc """
  Start a detector for a given source.
  """
  def start_link(opts) do
    source_id = Keyword.fetch!(opts, :source_id)
    learning_window = Keyword.get(opts, :learning_window, @default_learning_window)
    name = Keyword.get(opts, :name, via(source_id))

    GenServer.start_link(__MODULE__, %{source_id: source_id, learning_window: learning_window},
      name: name
    )
  end

  @doc """
  Process an event through drift detection.

  During the learning phase, the event is used to build the baseline schema.
  After learning, the event is compared against the baseline.

  Returns `:ok` — drift detection does not block event processing.
  """
  def process_event(source_id, event) do
    GenServer.cast(via(source_id), {:process_event, event})
  end

  @doc """
  Process an event through drift detection, addressed by pid or name.
  """
  def process_event_to(server, event) do
    GenServer.cast(server, {:process_event, event})
  end

  @doc """
  Get the current state of the detector (for testing/debugging).
  """
  def get_state(source_id) do
    GenServer.call(via(source_id), :get_state)
  end

  @doc """
  Get the current state addressed by pid or name.
  """
  def get_state_from(server) do
    GenServer.call(server, :get_state)
  end

  # --- GenServer Callbacks ---

  @impl true
  def init(%{source_id: source_id, learning_window: learning_window}) do
    # Try to load a persisted schema
    state =
      case Store.load_schema(source_id) do
        {:ok, {schema, fingerprint}} when is_map(schema) and map_size(schema) > 0 ->
          Logger.info("Loaded persisted schema for source #{source_id}")

          %{
            source_id: source_id,
            phase: :detecting,
            schema: schema,
            fingerprint: fingerprint,
            events_seen: 0,
            learning_window: learning_window
          }

        _ ->
          Logger.info("Starting schema learning for source #{source_id}")

          %{
            source_id: source_id,
            phase: :learning,
            schema: Schema.new(),
            fingerprint: nil,
            events_seen: 0,
            learning_window: learning_window
          }
      end

    {:ok, state}
  end

  @impl true
  def handle_cast({:process_event, event}, %{phase: :learning} = state) do
    schema = Schema.merge(state.schema, event)
    events_seen = state.events_seen + 1

    state = %{state | schema: schema, events_seen: events_seen}

    if events_seen >= state.learning_window do
      fingerprint = Schema.schema_fingerprint(schema)

      # Persist the learned schema
      try do
        Store.save_schema(state.source_id, schema, fingerprint)
      rescue
        e ->
          Logger.warning(
            "Failed to persist schema for #{state.source_id}: #{inspect(e)}"
          )
      end

      Logger.info(
        "Schema learning complete for source #{state.source_id} after #{events_seen} events"
      )

      {:noreply, %{state | phase: :detecting, fingerprint: fingerprint}}
    else
      {:noreply, state}
    end
  end

  def handle_cast({:process_event, event}, %{phase: :detecting} = state) do
    event_fingerprint = Schema.fingerprint(event)

    if event_fingerprint == state.fingerprint do
      # Fast path: fingerprint matches, no drift
      {:noreply, state}
    else
      # Slow path: deep comparison
      drifts = Schema.compare(state.schema, event)

      Enum.each(drifts, fn {drift_type, field_name, detail} ->
        {old_value, new_value} =
          case drift_type do
            :type_change ->
              {old_type, new_type} = detail
              {old_type, new_type}

            :new_field ->
              {nil, detail}

            :missing_field ->
              {field_name, nil}
          end

        drift_event =
          DriftEvent.new(%{
            source_id: state.source_id,
            drift_type: drift_type,
            field_name: field_name,
            old_value: old_value,
            new_value: new_value,
            sample_event: event
          })

        # Emit telemetry
        emit_telemetry(drift_type, state.source_id)

        # Broadcast via PubSub
        Alerter.broadcast_drift(drift_event, state.source_id)

        # Log the drift
        Logger.warning(
          "Schema drift detected for source #{state.source_id}: " <>
            "#{drift_type} on field '#{field_name}'"
        )

        # Persist drift event (best effort)
        try do
          Store.save_drift_event(drift_event)
        rescue
          e ->
            Logger.warning(
              "Failed to persist drift event for #{state.source_id}: #{inspect(e)}"
            )
        end
      end)

      {:noreply, state}
    end
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  # --- Private ---

  defp via(source_id) do
    {:via, Registry, {Compressr.Schema.Registry, source_id}}
  end

  defp emit_telemetry(drift_type, source_id) do
    :telemetry.execute(
      [:compressr, :schema, :drift_detected],
      %{count: 1},
      %{source_id: source_id}
    )

    case drift_type do
      :new_field ->
        :telemetry.execute(
          [:compressr, :schema, :fields_added],
          %{count: 1},
          %{source_id: source_id}
        )

      :missing_field ->
        :telemetry.execute(
          [:compressr, :schema, :fields_removed],
          %{count: 1},
          %{source_id: source_id}
        )

      :type_change ->
        :telemetry.execute(
          [:compressr, :schema, :type_changes],
          %{count: 1},
          %{source_id: source_id}
        )
    end
  end
end
