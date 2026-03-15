defmodule Compressr.Schema.Registry.LogTypeTest do
  use ExUnit.Case, async: true

  alias Compressr.Schema.Registry.LogType

  describe "new/1" do
    test "creates a log type with required fields" do
      fp = :crypto.hash(:sha256, "test")

      lt = LogType.new(%{
        id: "lt-1",
        source_id: "src-1",
        fingerprint: fp
      })

      assert lt.id == "lt-1"
      assert lt.source_id == "src-1"
      assert lt.fingerprint == fp
      assert lt.name == "lt-1"  # defaults to id
      assert lt.classification_method == :structural
      assert lt.event_count == 0
      assert lt.schema == %{}
      assert %DateTime{} = lt.first_seen
      assert %DateTime{} = lt.last_seen
    end

    test "creates a log type with all optional fields" do
      fp = :crypto.hash(:sha256, "test2")
      now = DateTime.utc_now()

      lt = LogType.new(%{
        id: "lt-2",
        name: "Custom Name",
        source_id: "src-2",
        fingerprint: fp,
        classification_method: :rule,
        first_seen: now,
        last_seen: now,
        event_count: 42,
        schema: %{"field" => %{type: :string}}
      })

      assert lt.name == "Custom Name"
      assert lt.classification_method == :rule
      assert lt.event_count == 42
      assert lt.first_seen == now
      assert lt.last_seen == now
      assert Map.has_key?(lt.schema, "field")
    end

    test "raises when missing required fields" do
      assert_raise KeyError, fn ->
        LogType.new(%{id: "lt-3", source_id: "src-3"})
      end
    end
  end

  describe "record_event/1" do
    test "increments event_count" do
      fp = :crypto.hash(:sha256, "test3")

      lt = LogType.new(%{
        id: "lt-rec",
        source_id: "src-rec",
        fingerprint: fp,
        event_count: 10
      })

      updated = LogType.record_event(lt)
      assert updated.event_count == 11
    end

    test "updates last_seen" do
      fp = :crypto.hash(:sha256, "test4")
      past = ~U[2020-01-01 00:00:00Z]

      lt = LogType.new(%{
        id: "lt-ls",
        source_id: "src-ls",
        fingerprint: fp,
        last_seen: past
      })

      :timer.sleep(10)
      updated = LogType.record_event(lt)
      assert DateTime.compare(updated.last_seen, past) == :gt
    end

    test "record_event multiple times accumulates" do
      fp = :crypto.hash(:sha256, "test5")

      lt = LogType.new(%{
        id: "lt-multi",
        source_id: "src-multi",
        fingerprint: fp,
        event_count: 0
      })

      result = Enum.reduce(1..5, lt, fn _, acc -> LogType.record_event(acc) end)
      assert result.event_count == 5
    end
  end
end
