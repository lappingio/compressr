defmodule Compressr.Schema.Registry.StoreTest do
  use ExUnit.Case, async: false

  alias Compressr.Schema.Registry.Store
  alias Compressr.Schema.Registry.{LogType, SchemaVersion}

  setup do
    clean_items("log_type")
    clean_items("schema_version")
    clean_items("field_avail")
    :ok
  end

  defp make_schema do
    now = DateTime.utc_now()

    %{
      "host" => %{type: :string, first_seen: now, sample_values: ["server1"]},
      "count" => %{type: :integer, first_seen: now, sample_values: [42]}
    }
  end

  defp make_log_type(source_id, id) do
    LogType.new(%{
      id: id,
      name: "Test Log Type #{id}",
      source_id: source_id,
      fingerprint: :crypto.hash(:sha256, id),
      classification_method: :structural,
      event_count: 100,
      schema: make_schema()
    })
  end

  describe "save_log_type/1 and load_log_types/1" do
    test "saves and loads a log type" do
      log_type = make_log_type("src-1", "lt-1")
      assert :ok = Store.save_log_type(log_type)

      {:ok, log_types} = Store.load_log_types("src-1")
      assert length(log_types) == 1

      [loaded] = log_types
      assert loaded.id == "lt-1"
      assert loaded.source_id == "src-1"
      assert loaded.event_count == 100
      assert loaded.classification_method == :structural
      assert is_map(loaded.schema)
      assert Map.has_key?(loaded.schema, "host")
      assert Map.has_key?(loaded.schema, "count")
    end

    test "loads multiple log types for a source" do
      Store.save_log_type(make_log_type("src-multi", "lt-a"))
      Store.save_log_type(make_log_type("src-multi", "lt-b"))

      {:ok, log_types} = Store.load_log_types("src-multi")
      assert length(log_types) == 2
      ids = Enum.map(log_types, & &1.id) |> Enum.sort()
      assert ids == ["lt-a", "lt-b"]
    end

    test "returns empty list when no log types exist" do
      {:ok, log_types} = Store.load_log_types("nonexistent-source")
      assert log_types == []
    end
  end

  describe "load_log_type/2" do
    test "loads a specific log type" do
      Store.save_log_type(make_log_type("src-get", "lt-specific"))

      {:ok, loaded} = Store.load_log_type("src-get", "lt-specific")
      assert loaded.id == "lt-specific"
      assert loaded.source_id == "src-get"
    end

    test "returns nil when log type not found" do
      {:ok, nil} = Store.load_log_type("nope", "nope")
    end
  end

  describe "save_schema_version/1 and load_schema_versions/2" do
    test "saves and loads schema versions" do
      version = %SchemaVersion{
        version: 1,
        log_type_id: "lt-v1",
        source_id: "src-v1",
        timestamp: DateTime.utc_now(),
        fields_added: ["host", "count"],
        fields_removed: [],
        type_changes: [],
        schema: make_schema()
      }

      assert :ok = Store.save_schema_version(version)

      {:ok, versions} = Store.load_schema_versions("src-v1", "lt-v1")
      assert length(versions) == 1

      [loaded] = versions
      assert loaded.version == 1
      assert loaded.log_type_id == "lt-v1"
      assert loaded.source_id == "src-v1"
      assert loaded.fields_added == ["host", "count"]
      assert loaded.fields_removed == []
      assert loaded.type_changes == []
    end

    test "loads versions sorted by version number" do
      for v <- [3, 1, 2] do
        version = %SchemaVersion{
          version: v,
          log_type_id: "lt-sorted",
          source_id: "src-sorted",
          timestamp: DateTime.utc_now(),
          fields_added: [],
          fields_removed: [],
          type_changes: [],
          schema: %{}
        }

        Store.save_schema_version(version)
      end

      {:ok, versions} = Store.load_schema_versions("src-sorted", "lt-sorted")
      assert length(versions) == 3
      version_nums = Enum.map(versions, & &1.version)
      assert version_nums == [1, 2, 3]
    end

    test "saves and loads type changes" do
      version = %SchemaVersion{
        version: 2,
        log_type_id: "lt-tc",
        source_id: "src-tc",
        timestamp: DateTime.utc_now(),
        fields_added: [],
        fields_removed: [],
        type_changes: [{"count", :integer, :string}],
        schema: make_schema()
      }

      Store.save_schema_version(version)

      {:ok, [loaded]} = Store.load_schema_versions("src-tc", "lt-tc")
      assert loaded.type_changes == [{"count", :integer, :string}]
    end

    test "returns empty list when no versions exist" do
      {:ok, versions} = Store.load_schema_versions("nope", "nope")
      assert versions == []
    end
  end

  describe "save_field_availability/4 and load_field_availability/2" do
    test "saves and loads field availability" do
      now = DateTime.utc_now()
      :ok = Store.save_field_availability("src-fa", "lt-fa", "hostname", now)

      {:ok, results} = Store.load_field_availability("src-fa", "hostname")
      assert length(results) == 1

      [result] = results
      assert result.source_id == "src-fa"
      assert result.log_type_id == "lt-fa"
      assert result.field_name == "hostname"
      assert %DateTime{} = result.first_seen
    end

    test "returns empty list when no availability exists" do
      {:ok, results} = Store.load_field_availability("nope", "nope")
      assert results == []
    end

    test "loads availability for multiple log types" do
      now = DateTime.utc_now()
      Store.save_field_availability("src-multi-fa", "lt-1", "host", now)
      Store.save_field_availability("src-multi-fa", "lt-2", "host", now)

      {:ok, results} = Store.load_field_availability("src-multi-fa", "host")
      assert length(results) == 2
    end
  end

  defp clean_items(prefix) do
    result =
      ExAws.Dynamo.scan("compressr_test_schemas",
        filter_expression: "pk = :pk",
        expression_attribute_values: [pk: prefix]
      )
      |> ExAws.request!()

    items = Map.get(result, "Items", [])

    Enum.each(items, fn item ->
      pk = get_in(item, ["pk", "S"])
      sk = get_in(item, ["sk", "S"])

      if pk && sk do
        ExAws.Dynamo.delete_item("compressr_test_schemas", %{"pk" => pk, "sk" => sk})
        |> ExAws.request!()
      end
    end)
  end
end
