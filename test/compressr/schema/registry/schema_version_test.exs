defmodule Compressr.Schema.Registry.SchemaVersionTest do
  use ExUnit.Case, async: true

  alias Compressr.Schema.Registry.SchemaVersion

  describe "create_version/5" do
    test "initial version captures all fields as added" do
      new_schema = %{
        "host" => %{type: :string, first_seen: DateTime.utc_now(), sample_values: ["server1"]},
        "level" => %{type: :string, first_seen: DateTime.utc_now(), sample_values: ["info"]},
        "count" => %{type: :integer, first_seen: DateTime.utc_now(), sample_values: [42]}
      }

      version = SchemaVersion.create_version("lt_1", "source_1", nil, new_schema, 1)

      assert version.version == 1
      assert version.log_type_id == "lt_1"
      assert version.source_id == "source_1"
      assert Enum.sort(version.fields_added) == ["count", "host", "level"]
      assert version.fields_removed == []
      assert version.type_changes == []
      assert version.schema == new_schema
    end

    test "detects added fields between versions" do
      old_schema = %{
        "host" => %{type: :string, first_seen: DateTime.utc_now(), sample_values: ["server1"]}
      }

      new_schema =
        Map.merge(old_schema, %{
          "level" => %{type: :string, first_seen: DateTime.utc_now(), sample_values: ["info"]}
        })

      version = SchemaVersion.create_version("lt_1", "source_1", old_schema, new_schema, 2)

      assert version.fields_added == ["level"]
      assert version.fields_removed == []
    end

    test "detects removed fields between versions" do
      old_schema = %{
        "host" => %{type: :string, first_seen: DateTime.utc_now(), sample_values: ["server1"]},
        "level" => %{type: :string, first_seen: DateTime.utc_now(), sample_values: ["info"]}
      }

      new_schema = %{
        "host" => %{type: :string, first_seen: DateTime.utc_now(), sample_values: ["server1"]}
      }

      version = SchemaVersion.create_version("lt_1", "source_1", old_schema, new_schema, 2)

      assert version.fields_added == []
      assert version.fields_removed == ["level"]
    end

    test "detects type changes between versions" do
      now = DateTime.utc_now()

      old_schema = %{
        "count" => %{type: :integer, first_seen: now, sample_values: [42]}
      }

      new_schema = %{
        "count" => %{type: :string, first_seen: now, sample_values: ["42"]}
      }

      version = SchemaVersion.create_version("lt_1", "source_1", old_schema, new_schema, 2)

      assert version.type_changes == [{"count", :integer, :string}]
    end

    test "detects multiple changes simultaneously" do
      now = DateTime.utc_now()

      old_schema = %{
        "host" => %{type: :string, first_seen: now, sample_values: ["server1"]},
        "count" => %{type: :integer, first_seen: now, sample_values: [42]},
        "removed_field" => %{type: :string, first_seen: now, sample_values: ["val"]}
      }

      new_schema = %{
        "host" => %{type: :string, first_seen: now, sample_values: ["server1"]},
        "count" => %{type: :string, first_seen: now, sample_values: ["42"]},
        "new_field" => %{type: :boolean, first_seen: now, sample_values: [true]}
      }

      version = SchemaVersion.create_version("lt_1", "source_1", old_schema, new_schema, 3)

      assert version.fields_added == ["new_field"]
      assert version.fields_removed == ["removed_field"]
      assert version.type_changes == [{"count", :integer, :string}]
    end
  end

  describe "get_field_availability/2" do
    test "finds field in initial version schema" do
      now = DateTime.utc_now()

      versions = [
        %SchemaVersion{
          version: 1,
          log_type_id: "lt_1",
          source_id: "source_1",
          timestamp: now,
          fields_added: ["host", "level"],
          fields_removed: [],
          type_changes: [],
          schema: %{
            "host" => %{type: :string, first_seen: now, sample_values: []},
            "level" => %{type: :string, first_seen: now, sample_values: []}
          }
        }
      ]

      assert {:ok, %{first_seen: ^now}} =
               SchemaVersion.get_field_availability(versions, "host")
    end

    test "finds field added in a later version" do
      t1 = ~U[2026-01-01 00:00:00Z]
      t2 = ~U[2026-03-01 00:00:00Z]

      versions = [
        %SchemaVersion{
          version: 1,
          log_type_id: "lt_1",
          source_id: "source_1",
          timestamp: t1,
          fields_added: ["host"],
          fields_removed: [],
          type_changes: [],
          schema: %{"host" => %{type: :string, first_seen: t1, sample_values: []}}
        },
        %SchemaVersion{
          version: 2,
          log_type_id: "lt_1",
          source_id: "source_1",
          timestamp: t2,
          fields_added: ["request_id"],
          fields_removed: [],
          type_changes: [],
          schema: %{
            "host" => %{type: :string, first_seen: t1, sample_values: []},
            "request_id" => %{type: :string, first_seen: t2, sample_values: []}
          }
        }
      ]

      assert {:ok, %{first_seen: ^t2}} =
               SchemaVersion.get_field_availability(versions, "request_id")
    end

    test "returns :not_found for field that never existed" do
      versions = [
        %SchemaVersion{
          version: 1,
          log_type_id: "lt_1",
          source_id: "source_1",
          timestamp: DateTime.utc_now(),
          fields_added: ["host"],
          fields_removed: [],
          type_changes: [],
          schema: %{"host" => %{type: :string, first_seen: DateTime.utc_now(), sample_values: []}}
        }
      ]

      assert :not_found = SchemaVersion.get_field_availability(versions, "nonexistent")
    end

    test "finds field in version 1 schema even if not in fields_added" do
      now = DateTime.utc_now()

      # Manually construct version where fields_added doesn't include all schema keys
      versions = [
        %SchemaVersion{
          version: 1,
          log_type_id: "lt_1",
          source_id: "source_1",
          timestamp: now,
          fields_added: [],
          fields_removed: [],
          type_changes: [],
          schema: %{
            "host" => %{type: :string, first_seen: now, sample_values: []}
          }
        }
      ]

      assert {:ok, %{first_seen: ^now}} =
               SchemaVersion.get_field_availability(versions, "host")
    end

    test "returns not_found for empty versions list" do
      assert :not_found = SchemaVersion.get_field_availability([], "anything")
    end

    test "handles versions out of order" do
      t1 = ~U[2026-01-01 00:00:00Z]
      t2 = ~U[2026-02-01 00:00:00Z]

      # Pass versions out of order -- should still work
      versions = [
        %SchemaVersion{
          version: 2,
          log_type_id: "lt_1",
          source_id: "source_1",
          timestamp: t2,
          fields_added: ["level"],
          fields_removed: [],
          type_changes: [],
          schema: %{
            "host" => %{type: :string, first_seen: t1, sample_values: []},
            "level" => %{type: :string, first_seen: t2, sample_values: []}
          }
        },
        %SchemaVersion{
          version: 1,
          log_type_id: "lt_1",
          source_id: "source_1",
          timestamp: t1,
          fields_added: ["host"],
          fields_removed: [],
          type_changes: [],
          schema: %{"host" => %{type: :string, first_seen: t1, sample_values: []}}
        }
      ]

      # Should find "host" in version 1 (sorted internally)
      assert {:ok, %{first_seen: ^t1}} =
               SchemaVersion.get_field_availability(versions, "host")

      assert {:ok, %{first_seen: ^t2}} =
               SchemaVersion.get_field_availability(versions, "level")
    end
  end
end
