defmodule Compressr.Schema.DetectorTest do
  use ExUnit.Case, async: false

  alias Compressr.Schema.Detector
  alias Compressr.Schema.Alerter

  setup do
    # Subscribe to drift events so we can verify broadcasts
    Alerter.subscribe()

    :ok
  end

  defp start_detector(opts \\ []) do
    source_id = Keyword.get(opts, :source_id, "test-source-#{:erlang.unique_integer([:positive])}")
    learning_window = Keyword.get(opts, :learning_window, 3)

    {:ok, pid} =
      Detector.start_link(
        source_id: source_id,
        learning_window: learning_window,
        name: nil
      )

    %{pid: pid, source_id: source_id}
  end

  describe "learning phase" do
    test "starts in learning phase" do
      %{pid: pid} = start_detector()

      state = Detector.get_state_from(pid)
      assert state.phase == :learning
      assert state.events_seen == 0
    end

    test "accumulates schema from events during learning" do
      %{pid: pid} = start_detector(learning_window: 3)

      Detector.process_event_to(pid, %{"host" => "server1", "level" => "info"})
      # Give the cast time to process
      :timer.sleep(10)

      state = Detector.get_state_from(pid)
      assert state.phase == :learning
      assert state.events_seen == 1
      assert Map.has_key?(state.schema, "host")
      assert Map.has_key?(state.schema, "level")
    end

    test "transitions to detecting phase after learning window" do
      %{pid: pid} = start_detector(learning_window: 3)

      for i <- 1..3 do
        Detector.process_event_to(pid, %{"host" => "server#{i}", "level" => "info"})
      end

      :timer.sleep(50)

      state = Detector.get_state_from(pid)
      assert state.phase == :detecting
      assert state.events_seen == 3
      assert state.fingerprint != nil
    end

    test "learns schema across multiple events with different values" do
      %{pid: pid} = start_detector(learning_window: 2)

      Detector.process_event_to(pid, %{"host" => "server1", "level" => "info"})
      Detector.process_event_to(pid, %{"host" => "server2", "level" => "error"})
      :timer.sleep(50)

      state = Detector.get_state_from(pid)
      assert state.phase == :detecting
      assert state.schema["host"].type == :string
      assert state.schema["level"].type == :string
    end
  end

  describe "drift detection (post-learning)" do
    setup do
      %{pid: pid} = ctx = start_detector(learning_window: 2)

      # Learn from 2 events
      Detector.process_event_to(pid, %{"host" => "server1", "level" => "info", "count" => 42})
      Detector.process_event_to(pid, %{"host" => "server2", "level" => "error", "count" => 10})
      :timer.sleep(50)

      # Verify we're in detecting phase
      state = Detector.get_state_from(pid)
      assert state.phase == :detecting

      ctx
    end

    test "fast path: matching fingerprint produces no drift", %{pid: pid} do
      # Same structure, different values
      Detector.process_event_to(pid, %{"host" => "server3", "level" => "warn", "count" => 99})
      :timer.sleep(50)

      # No drift event should have been broadcast
      refute_received {:schema_drift, _}
    end

    test "detects new field added", %{pid: pid} do
      Detector.process_event_to(pid, %{
        "host" => "server3",
        "level" => "warn",
        "count" => 99,
        "new_field" => "surprise"
      })

      :timer.sleep(50)

      assert_received {:schema_drift, drift_event}
      assert drift_event.drift_type == :new_field
      assert drift_event.field_name == "new_field"
    end

    test "detects field removed", %{pid: pid} do
      # Send event missing "count" field
      Detector.process_event_to(pid, %{"host" => "server3", "level" => "warn"})
      :timer.sleep(50)

      assert_received {:schema_drift, drift_event}
      assert drift_event.drift_type == :missing_field
      assert drift_event.field_name == "count"
    end

    test "detects type change (integer to string)", %{pid: pid} do
      Detector.process_event_to(pid, %{
        "host" => "server3",
        "level" => "warn",
        "count" => "not_a_number"
      })

      :timer.sleep(50)

      assert_received {:schema_drift, drift_event}
      assert drift_event.drift_type == :type_change
      assert drift_event.field_name == "count"
      assert drift_event.old_value == :integer
      assert drift_event.new_value == :string
    end

    test "detects multiple drifts in a single event", %{pid: pid} do
      # Missing count, new field, type change on host
      Detector.process_event_to(pid, %{
        "host" => 12345,
        "level" => "info",
        "brand_new" => "field"
      })

      :timer.sleep(50)

      # Collect all drift messages
      drift_events = collect_drift_events()

      drift_types = Enum.map(drift_events, & &1.drift_type)
      assert :new_field in drift_types
      assert :missing_field in drift_types
      assert :type_change in drift_types
    end

    test "includes sample event in drift event", %{pid: pid} do
      event = %{
        "host" => "server3",
        "level" => "warn",
        "count" => 99,
        "new_field" => "surprise"
      }

      Detector.process_event_to(pid, event)
      :timer.sleep(50)

      assert_received {:schema_drift, drift_event}
      assert drift_event.sample_event == event
    end
  end

  # Collect all drift events from the mailbox
  defp collect_drift_events(acc \\ []) do
    receive do
      {:schema_drift, event} -> collect_drift_events([event | acc])
    after
      100 -> Enum.reverse(acc)
    end
  end
end
