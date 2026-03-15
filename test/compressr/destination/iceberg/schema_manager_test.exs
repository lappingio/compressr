defmodule Compressr.Destination.Iceberg.SchemaManagerTest do
  use ExUnit.Case, async: true

  alias Compressr.Destination.Iceberg.SchemaManager

  describe "infer_schema/1" do
    test "infers string type from string values" do
      events = [%{"host" => "server1", "_time" => 1_000_000}]
      schema = SchemaManager.infer_schema(events)

      host_field = Enum.find(schema, &(&1.name == "host"))
      assert host_field.type == :string
      assert host_field.nullable == true
    end

    test "infers integer type from small integers" do
      events = [%{"status" => 200, "_time" => 1_000_000}]
      schema = SchemaManager.infer_schema(events)

      field = Enum.find(schema, &(&1.name == "status"))
      assert field.type == :integer
    end

    test "infers long type from large integers" do
      events = [%{"big_id" => 9_999_999_999, "_time" => 1_000_000}]
      schema = SchemaManager.infer_schema(events)

      field = Enum.find(schema, &(&1.name == "big_id"))
      assert field.type == :long
    end

    test "infers double type from floats" do
      events = [%{"latency" => 1.5, "_time" => 1_000_000}]
      schema = SchemaManager.infer_schema(events)

      field = Enum.find(schema, &(&1.name == "latency"))
      assert field.type == :double
    end

    test "infers boolean type" do
      events = [%{"active" => true, "_time" => 1_000_000}]
      schema = SchemaManager.infer_schema(events)

      field = Enum.find(schema, &(&1.name == "active"))
      assert field.type == :boolean
    end

    test "infers timestamp type from ISO 8601 strings" do
      events = [%{"created_at" => "2026-03-15T10:30:00Z", "_time" => 1_000_000}]
      schema = SchemaManager.infer_schema(events)

      field = Enum.find(schema, &(&1.name == "created_at"))
      assert field.type == :timestamp
    end

    test "excludes _raw field" do
      events = [%{"_raw" => "raw data", "host" => "server1", "_time" => 1_000_000}]
      schema = SchemaManager.infer_schema(events)

      refute Enum.any?(schema, &(&1.name == "_raw"))
    end

    test "excludes internal __ fields" do
      events = [%{"__source_id" => "src1", "host" => "server1", "_time" => 1_000_000}]
      schema = SchemaManager.infer_schema(events)

      refute Enum.any?(schema, &(&1.name == "__source_id"))
    end

    test "includes _time field" do
      events = [%{"_time" => 1_000_000}]
      schema = SchemaManager.infer_schema(events)

      field = Enum.find(schema, &(&1.name == "_time"))
      assert field != nil
    end

    test "builds union of fields from multiple events" do
      events = [
        %{"host" => "server1", "_time" => 1_000_000},
        %{"host" => "server2", "region" => "us-east-1", "_time" => 1_000_001}
      ]

      schema = SchemaManager.infer_schema(events)
      names = Enum.map(schema, & &1.name)

      assert "host" in names
      assert "region" in names
      assert "_time" in names
    end

    test "returns fields sorted by name" do
      events = [%{"zebra" => "z", "alpha" => "a", "_time" => 1}]
      schema = SchemaManager.infer_schema(events)
      names = Enum.map(schema, & &1.name)

      assert names == Enum.sort(names)
    end

    test "infers string for nil values" do
      events = [%{"maybe" => nil, "_time" => 1}]
      schema = SchemaManager.infer_schema(events)

      field = Enum.find(schema, &(&1.name == "maybe"))
      assert field.type == :string
    end
  end

  describe "evolve_schema/2" do
    test "detects new fields" do
      current = [
        %{name: "_time", type: :long, nullable: true},
        %{name: "host", type: :string, nullable: true}
      ]

      new_events = [%{"host" => "server1", "region" => "us-east-1", "_time" => 1}]

      {:ok, updated, new_fields} = SchemaManager.evolve_schema(current, new_events)

      assert length(new_fields) == 1
      assert hd(new_fields).name == "region"
      assert length(updated) == 3
    end

    test "returns empty new_fields when no evolution needed" do
      current = [
        %{name: "_time", type: :long, nullable: true},
        %{name: "host", type: :string, nullable: true}
      ]

      new_events = [%{"host" => "server1", "_time" => 1}]

      {:ok, updated, new_fields} = SchemaManager.evolve_schema(current, new_events)

      assert new_fields == []
      assert length(updated) == 2
    end

    test "preserves existing fields when adding new ones" do
      current = [
        %{name: "host", type: :string, nullable: true}
      ]

      new_events = [%{"region" => "us-east-1", "_time" => 1}]

      {:ok, updated, _new_fields} = SchemaManager.evolve_schema(current, new_events)

      host = Enum.find(updated, &(&1.name == "host"))
      assert host.type == :string
    end

    test "result is sorted by field name" do
      current = [%{name: "zebra", type: :string, nullable: true}]
      new_events = [%{"alpha" => "a", "_time" => 1}]

      {:ok, updated, _} = SchemaManager.evolve_schema(current, new_events)
      names = Enum.map(updated, & &1.name)
      assert names == Enum.sort(names)
    end
  end

  describe "infer_type/1" do
    test "boolean before integer" do
      assert SchemaManager.infer_type(true) == :boolean
      assert SchemaManager.infer_type(false) == :boolean
    end

    test "integer for small ints" do
      assert SchemaManager.infer_type(42) == :integer
      assert SchemaManager.infer_type(-100) == :integer
    end

    test "long for large ints" do
      assert SchemaManager.infer_type(3_000_000_000) == :long
    end

    test "double for floats" do
      assert SchemaManager.infer_type(3.14) == :double
    end

    test "string for plain strings" do
      assert SchemaManager.infer_type("hello") == :string
    end

    test "timestamp for ISO 8601 strings" do
      assert SchemaManager.infer_type("2026-03-15T00:00:00Z") == :timestamp
    end

    test "string for nil" do
      assert SchemaManager.infer_type(nil) == :string
    end
  end
end
