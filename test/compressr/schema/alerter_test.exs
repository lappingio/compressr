defmodule Compressr.Schema.AlerterTest do
  use ExUnit.Case, async: false

  alias Compressr.Schema.Alerter
  alias Compressr.Schema.DriftEvent

  defp make_drift_event(overrides \\ %{}) do
    DriftEvent.new(
      Map.merge(
        %{
          source_id: "test-source",
          drift_type: :new_field,
          field_name: "new_field",
          old_value: nil,
          new_value: :string
        },
        overrides
      )
    )
  end

  describe "subscribe/0 and broadcast_drift/1" do
    test "subscriber receives drift events on the general topic" do
      :ok = Alerter.subscribe()

      drift_event = make_drift_event()
      :ok = Alerter.broadcast_drift(drift_event)

      assert_receive {:schema_drift, received_event}
      assert received_event.source_id == "test-source"
      assert received_event.drift_type == :new_field
      assert received_event.field_name == "new_field"
    end

    test "multiple subscribers all receive the event" do
      parent = self()

      # Start two subscriber tasks
      for i <- 1..2 do
        Task.start(fn ->
          :ok = Alerter.subscribe()
          send(parent, {:subscribed, i})

          receive do
            {:schema_drift, event} -> send(parent, {:received, i, event})
          end
        end)
      end

      # Wait for both to subscribe
      assert_receive {:subscribed, 1}
      assert_receive {:subscribed, 2}

      drift_event = make_drift_event()
      :ok = Alerter.broadcast_drift(drift_event)

      assert_receive {:received, 1, _event}
      assert_receive {:received, 2, _event}
    end
  end

  describe "subscribe/1 and broadcast_drift/2 (source-specific)" do
    test "subscriber on source topic receives source-specific drift events" do
      :ok = Alerter.subscribe("source-abc")

      drift_event = make_drift_event(%{source_id: "source-abc"})
      :ok = Alerter.broadcast_drift(drift_event, "source-abc")

      assert_receive {:schema_drift, received_event}
      assert received_event.source_id == "source-abc"
    end

    test "general subscriber also receives source-specific drift events" do
      :ok = Alerter.subscribe()

      drift_event = make_drift_event(%{source_id: "source-xyz"})
      :ok = Alerter.broadcast_drift(drift_event, "source-xyz")

      # General topic gets the event
      assert_receive {:schema_drift, received_event}
      assert received_event.source_id == "source-xyz"
    end

    test "subscriber on different source topic does not receive events" do
      :ok = Alerter.subscribe("source-other")

      drift_event = make_drift_event(%{source_id: "source-abc"})
      :ok = Alerter.broadcast_drift(drift_event, "source-abc")

      refute_receive {:schema_drift, _}, 50
    end
  end

  describe "broadcast_drift/2 broadcasts to both topics" do
    test "broadcasts to general and source-specific topics" do
      :ok = Alerter.subscribe()
      :ok = Alerter.subscribe("source-dual")

      drift_event = make_drift_event(%{source_id: "source-dual"})
      :ok = Alerter.broadcast_drift(drift_event, "source-dual")

      # Should receive on both topics
      assert_receive {:schema_drift, _event1}
      assert_receive {:schema_drift, _event2}
    end
  end

  describe "broadcast with different drift types" do
    test "broadcasts missing_field events" do
      :ok = Alerter.subscribe()

      drift_event = make_drift_event(%{drift_type: :missing_field, field_name: "removed_field"})
      :ok = Alerter.broadcast_drift(drift_event)

      assert_receive {:schema_drift, event}
      assert event.drift_type == :missing_field
    end

    test "broadcasts type_change events" do
      :ok = Alerter.subscribe()

      drift_event = make_drift_event(%{
        drift_type: :type_change,
        field_name: "count",
        old_value: :integer,
        new_value: :string
      })

      :ok = Alerter.broadcast_drift(drift_event)

      assert_receive {:schema_drift, event}
      assert event.drift_type == :type_change
      assert event.old_value == :integer
      assert event.new_value == :string
    end
  end
end
