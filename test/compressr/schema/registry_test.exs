defmodule Compressr.Schema.RegistryTest do
  use ExUnit.Case, async: true

  alias Compressr.Schema.Registry
  alias Compressr.Schema.Registry.{LogType, SchemaVersion, VolumeTracker}

  describe "discover/3" do
    test "classifies events and returns discovery report" do
      events = [
        %{"host" => "server1", "level" => "info", "_time" => 1},
        %{"host" => "server2", "level" => "error", "_time" => 2},
        %{"request_path" => "/api", "status_code" => 200, "_time" => 3},
        %{"request_path" => "/health", "status_code" => 200, "_time" => 4}
      ]

      report = Registry.discover("source-1", events)

      assert report.source_id == "source-1"
      assert report.total_events == 4
      assert length(report.log_types) == 2

      # Each log type should have the correct event count
      counts = Enum.map(report.log_types, & &1.event_count) |> Enum.sort()
      assert counts == [2, 2]
    end

    test "infers per-type schemas correctly" do
      events = [
        %{"host" => "server1", "level" => "info"},
        %{"request_path" => "/api", "status_code" => 200}
      ]

      report = Registry.discover("source-1", events)

      # Find each log type
      log_types = report.log_types

      # One log type should have host+level, the other request_path+status_code
      schemas = Enum.map(log_types, fn lt -> Map.keys(lt.schema) |> Enum.sort() end)

      assert ["host", "level"] in schemas
      assert ["request_path", "status_code"] in schemas
    end

    test "discovers with classification rules" do
      rules = [
        {:field_presence,
         %{fields: ["request_path", "status_code"], log_type_id: "http_access"}}
      ]

      events = [
        %{"request_path" => "/api", "status_code" => 200},
        %{"request_path" => "/health", "status_code" => 200},
        %{"host" => "server1", "level" => "info"}
      ]

      report = Registry.discover("source-1", events, rules: rules)

      assert length(report.log_types) == 2

      http_type = Enum.find(report.log_types, fn lt -> lt.id == "http_access" end)
      assert http_type != nil
      assert http_type.event_count == 2
    end

    test "records volume when tracker provided" do
      {:ok, tracker} = VolumeTracker.start_link(name: nil, window_seconds: 60)

      events = [
        %{"host" => "server1", "level" => "info"},
        %{"host" => "server2", "level" => "error"},
        %{"request_path" => "/api", "status_code" => 200}
      ]

      Registry.discover("source-1", events, volume_tracker: tracker)

      # Allow casts to process
      :timer.sleep(20)

      breakdown = VolumeTracker.get_breakdown(tracker, "source-1")

      # Should have entries for the log types
      assert map_size(breakdown) == 2
    end

    test "handles empty event list" do
      report = Registry.discover("source-1", [])

      assert report.source_id == "source-1"
      assert report.total_events == 0
      assert report.log_types == []
    end

    test "single event type" do
      events = [
        %{"host" => "server1", "level" => "info"},
        %{"host" => "server2", "level" => "error"},
        %{"host" => "server3", "level" => "warn"}
      ]

      report = Registry.discover("source-1", events)

      assert length(report.log_types) == 1
      assert hd(report.log_types).event_count == 3
    end
  end

  describe "get_log_types/2" do
    test "filters log types by source_id" do
      log_types = [
        LogType.new(%{
          id: "lt1",
          source_id: "source-1",
          fingerprint: :crypto.hash(:sha256, "a")
        }),
        LogType.new(%{
          id: "lt2",
          source_id: "source-1",
          fingerprint: :crypto.hash(:sha256, "b")
        }),
        LogType.new(%{
          id: "lt3",
          source_id: "source-2",
          fingerprint: :crypto.hash(:sha256, "c")
        })
      ]

      result = Registry.get_log_types("source-1", log_types)

      assert length(result) == 2
      assert Enum.all?(result, fn lt -> lt.source_id == "source-1" end)
    end

    test "returns empty list for unknown source" do
      log_types = [
        LogType.new(%{
          id: "lt1",
          source_id: "source-1",
          fingerprint: :crypto.hash(:sha256, "a")
        })
      ]

      assert Registry.get_log_types("unknown", log_types) == []
    end
  end

  describe "get_schema/3" do
    test "returns schema for matching log type" do
      now = DateTime.utc_now()

      schema = %{
        "host" => %{type: :string, first_seen: now, sample_values: ["server1"]}
      }

      log_types = [
        LogType.new(%{
          id: "lt1",
          source_id: "source-1",
          fingerprint: :crypto.hash(:sha256, "a"),
          schema: schema
        })
      ]

      assert {:ok, ^schema} = Registry.get_schema("source-1", "lt1", log_types)
    end

    test "returns :not_found for missing log type" do
      log_types = [
        LogType.new(%{
          id: "lt1",
          source_id: "source-1",
          fingerprint: :crypto.hash(:sha256, "a")
        })
      ]

      assert :not_found = Registry.get_schema("source-1", "lt2", log_types)
    end

    test "returns :not_found for wrong source" do
      log_types = [
        LogType.new(%{
          id: "lt1",
          source_id: "source-1",
          fingerprint: :crypto.hash(:sha256, "a")
        })
      ]

      assert :not_found = Registry.get_schema("source-2", "lt1", log_types)
    end
  end

  describe "search_fields/2" do
    test "finds field across multiple log types" do
      now = DateTime.utc_now()

      log_types = [
        LogType.new(%{
          id: "http_access",
          name: "HTTP Access",
          source_id: "source-1",
          fingerprint: :crypto.hash(:sha256, "a"),
          schema: %{
            "status" => %{type: :integer, first_seen: now, sample_values: [200]},
            "request_path" => %{type: :string, first_seen: now, sample_values: ["/api"]}
          }
        }),
        LogType.new(%{
          id: "sshd_auth",
          name: "SSH Auth",
          source_id: "source-1",
          fingerprint: :crypto.hash(:sha256, "b"),
          schema: %{
            "status" => %{type: :string, first_seen: now, sample_values: ["success"]},
            "user" => %{type: :string, first_seen: now, sample_values: ["root"]}
          }
        }),
        LogType.new(%{
          id: "kernel",
          name: "Kernel",
          source_id: "source-1",
          fingerprint: :crypto.hash(:sha256, "c"),
          schema: %{
            "message" => %{type: :string, first_seen: now, sample_values: ["oom"]}
          }
        })
      ]

      results = Registry.search_fields("status", log_types)

      assert length(results) == 2

      log_type_ids = Enum.map(results, & &1.log_type_id) |> Enum.sort()
      assert log_type_ids == ["http_access", "sshd_auth"]

      # Check that field type info is included
      http_result = Enum.find(results, fn r -> r.log_type_id == "http_access" end)
      assert http_result.field_type == :integer
      assert http_result.sample_values == [200]
    end

    test "returns empty list when field not found" do
      log_types = [
        LogType.new(%{
          id: "lt1",
          source_id: "source-1",
          fingerprint: :crypto.hash(:sha256, "a"),
          schema: %{
            "host" => %{type: :string, first_seen: DateTime.utc_now(), sample_values: []}
          }
        })
      ]

      assert Registry.search_fields("nonexistent", log_types) == []
    end
  end

  describe "get_schema_history/1" do
    test "returns versions sorted by version number" do
      v1 = %SchemaVersion{
        version: 1,
        log_type_id: "lt_1",
        source_id: "source_1",
        timestamp: ~U[2026-01-01 00:00:00Z],
        fields_added: ["host"],
        schema: %{}
      }

      v3 = %SchemaVersion{
        version: 3,
        log_type_id: "lt_1",
        source_id: "source_1",
        timestamp: ~U[2026-03-01 00:00:00Z],
        fields_added: ["request_id"],
        schema: %{}
      }

      v2 = %SchemaVersion{
        version: 2,
        log_type_id: "lt_1",
        source_id: "source_1",
        timestamp: ~U[2026-02-01 00:00:00Z],
        fields_added: ["level"],
        schema: %{}
      }

      history = Registry.get_schema_history([v3, v1, v2])

      assert Enum.map(history, & &1.version) == [1, 2, 3]
    end

    test "handles empty version list" do
      assert Registry.get_schema_history([]) == []
    end
  end

  describe "get_volume_breakdown/2" do
    test "delegates to VolumeTracker" do
      {:ok, tracker} = VolumeTracker.start_link(name: nil, window_seconds: 60)

      VolumeTracker.record(tracker, "source-1", "http_access", 100)
      VolumeTracker.record(tracker, "source-1", "syslog", 80)

      :timer.sleep(10)

      breakdown = Registry.get_volume_breakdown(tracker, "source-1")

      assert Map.has_key?(breakdown, "http_access")
      assert Map.has_key?(breakdown, "syslog")
    end
  end
end
