defmodule Compressr.Schema.DetectorExtraTest do
  use ExUnit.Case, async: false

  alias Compressr.Schema.Detector
  alias Compressr.Schema.Alerter
  alias Compressr.Schema.{Schema, Store}

  setup do
    Alerter.subscribe()
    :ok
  end

  defp start_detector(opts \\ []) do
    source_id = Keyword.get(opts, :source_id, "det-extra-#{:erlang.unique_integer([:positive])}")
    learning_window = Keyword.get(opts, :learning_window, 2)

    {:ok, pid} =
      Detector.start_link(
        source_id: source_id,
        learning_window: learning_window,
        name: nil
      )

    %{pid: pid, source_id: source_id}
  end

  describe "drift detection with type changes" do
    setup do
      %{pid: pid} = ctx = start_detector(learning_window: 2)

      # Learn schema with mixed types
      Detector.process_event_to(pid, %{"count" => 42, "active" => true, "tags" => ["a", "b"]})
      Detector.process_event_to(pid, %{"count" => 10, "active" => false, "tags" => ["c"]})
      :timer.sleep(50)

      state = Detector.get_state_from(pid)
      assert state.phase == :detecting

      ctx
    end

    test "detects boolean to string type change", %{pid: pid} do
      Detector.process_event_to(pid, %{"count" => 5, "active" => "yes", "tags" => ["d"]})
      :timer.sleep(50)

      events = collect_drift_events()
      type_changes = Enum.filter(events, &(&1.drift_type == :type_change))
      assert Enum.any?(type_changes, &(&1.field_name == "active"))
    end

    test "detects list to string type change", %{pid: pid} do
      Detector.process_event_to(pid, %{"count" => 5, "active" => true, "tags" => "single"})
      :timer.sleep(50)

      events = collect_drift_events()
      type_changes = Enum.filter(events, &(&1.drift_type == :type_change))
      assert Enum.any?(type_changes, &(&1.field_name == "tags"))
    end

    test "detects integer to float type change", %{pid: pid} do
      Detector.process_event_to(pid, %{"count" => 3.14, "active" => true, "tags" => ["e"]})
      :timer.sleep(50)

      events = collect_drift_events()
      type_changes = Enum.filter(events, &(&1.drift_type == :type_change))
      assert Enum.any?(type_changes, &(&1.field_name == "count"))
    end
  end

  describe "learning window of 1" do
    test "transitions to detecting after a single event" do
      %{pid: pid} = start_detector(learning_window: 1)

      Detector.process_event_to(pid, %{"x" => 1})
      :timer.sleep(50)

      state = Detector.get_state_from(pid)
      assert state.phase == :detecting
      assert state.events_seen == 1
    end
  end

  describe "nil field values" do
    test "nil values do not trigger type change drift" do
      %{pid: pid} = start_detector(learning_window: 2)

      Detector.process_event_to(pid, %{"host" => "a", "port" => 80})
      Detector.process_event_to(pid, %{"host" => "b", "port" => 443})
      :timer.sleep(50)

      # Send event with nil port - nil is excluded from type change detection
      Detector.process_event_to(pid, %{"host" => "c", "port" => nil})
      :timer.sleep(50)

      events = collect_drift_events()
      type_changes = Enum.filter(events, &(&1.drift_type == :type_change && &1.field_name == "port"))
      assert type_changes == []
    end
  end

  describe "source_id tracking" do
    test "state contains correct source_id" do
      %{pid: pid, source_id: source_id} = start_detector()
      state = Detector.get_state_from(pid)
      assert state.source_id == source_id
    end
  end

  describe "empty events" do
    test "handles event with no user fields during learning" do
      %{pid: pid} = start_detector(learning_window: 2)

      # Events with only internal fields
      Detector.process_event_to(pid, %{"_raw" => "test", "_time" => 123})
      Detector.process_event_to(pid, %{"_raw" => "test2", "_time" => 124})
      :timer.sleep(50)

      state = Detector.get_state_from(pid)
      assert state.phase == :detecting
      assert state.schema == %{}
    end
  end

  describe "init with persisted schema" do
    test "starts in detecting phase when persisted schema exists" do
      source_id = "det-persisted-#{:erlang.unique_integer([:positive])}"

      # Build a schema and persist it
      schema = Schema.new()
      schema = Schema.merge(schema, %{"host" => "server1", "level" => "info"})
      fingerprint = Schema.schema_fingerprint(schema)

      Store.save_schema(source_id, schema, fingerprint)

      # Start detector for this source - should load persisted schema
      {:ok, pid} =
        Detector.start_link(
          source_id: source_id,
          learning_window: 1000,
          name: nil
        )

      state = Detector.get_state_from(pid)
      assert state.phase == :detecting
      assert state.fingerprint == fingerprint
      assert Map.has_key?(state.schema, "host")
      assert Map.has_key?(state.schema, "level")

      GenServer.stop(pid)
    end

    test "starts in learning phase when no persisted schema exists" do
      source_id = "det-no-persist-#{:erlang.unique_integer([:positive])}"

      {:ok, pid} =
        Detector.start_link(
          source_id: source_id,
          learning_window: 5,
          name: nil
        )

      state = Detector.get_state_from(pid)
      assert state.phase == :learning
      assert state.fingerprint == nil

      GenServer.stop(pid)
    end
  end

  describe "telemetry emission" do
    test "emits telemetry on drift detection" do
      ref = :telemetry_test.attach_event_handlers(self(), [
        [:compressr, :schema, :drift_detected],
        [:compressr, :schema, :fields_added],
        [:compressr, :schema, :fields_removed],
        [:compressr, :schema, :type_changes]
      ])

      %{pid: pid} = start_detector(learning_window: 1)

      Detector.process_event_to(pid, %{"host" => "s1", "count" => 42})
      :timer.sleep(50)

      # Trigger drift
      Detector.process_event_to(pid, %{"host" => "s1", "count" => 42, "new_field" => "x"})
      :timer.sleep(50)

      assert_receive {[:compressr, :schema, :drift_detected], ^ref, %{count: 1}, _meta}
      assert_receive {[:compressr, :schema, :fields_added], ^ref, %{count: 1}, _meta}

      GenServer.stop(pid)
    end
  end

  defp collect_drift_events(acc \\ []) do
    receive do
      {:schema_drift, event} -> collect_drift_events([event | acc])
    after
      100 -> Enum.reverse(acc)
    end
  end
end
