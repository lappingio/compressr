defmodule Compressr.Schema.SchemaTest do
  use ExUnit.Case, async: true

  alias Compressr.Schema.Schema

  describe "infer_type/1" do
    test "infers string type" do
      assert Schema.infer_type("hello") == :string
      assert Schema.infer_type("") == :string
    end

    test "infers integer type" do
      assert Schema.infer_type(42) == :integer
      assert Schema.infer_type(0) == :integer
      assert Schema.infer_type(-1) == :integer
    end

    test "infers float type" do
      assert Schema.infer_type(3.14) == :float
      assert Schema.infer_type(0.0) == :float
    end

    test "infers boolean type" do
      assert Schema.infer_type(true) == :boolean
      assert Schema.infer_type(false) == :boolean
    end

    test "infers map type" do
      assert Schema.infer_type(%{"key" => "value"}) == :map
      assert Schema.infer_type(%{}) == :map
    end

    test "infers list type" do
      assert Schema.infer_type([1, 2, 3]) == :list
      assert Schema.infer_type([]) == :list
    end

    test "infers nil type" do
      assert Schema.infer_type(nil) == :nil
    end
  end

  describe "merge/2" do
    test "adds new fields from event to empty schema" do
      schema = Schema.new()
      event = %{"host" => "server1", "level" => "info", "_time" => 123}

      result = Schema.merge(schema, event)

      assert Map.has_key?(result, "host")
      assert Map.has_key?(result, "level")
      # Internal fields should be excluded
      refute Map.has_key?(result, "_time")
    end

    test "infers correct types for new fields" do
      schema = Schema.new()

      event = %{
        "host" => "server1",
        "count" => 42,
        "ratio" => 0.5,
        "active" => true,
        "tags" => ["a", "b"],
        "meta" => %{"key" => "val"}
      }

      result = Schema.merge(schema, event)

      assert result["host"].type == :string
      assert result["count"].type == :integer
      assert result["ratio"].type == :float
      assert result["active"].type == :boolean
      assert result["tags"].type == :list
      assert result["meta"].type == :map
    end

    test "accumulates sample values up to max" do
      schema = Schema.new()

      schema =
        Enum.reduce(1..10, schema, fn i, acc ->
          Schema.merge(acc, %{"host" => "server#{i}"})
        end)

      # Max is 5 samples
      assert length(schema["host"].sample_values) == 5
    end

    test "preserves existing field info on merge" do
      schema = Schema.new()
      schema = Schema.merge(schema, %{"host" => "server1"})
      first_seen = schema["host"].first_seen

      schema = Schema.merge(schema, %{"host" => "server2"})

      assert schema["host"].first_seen == first_seen
      assert schema["host"].type == :string
    end

    test "excludes system fields" do
      schema = Schema.new()
      event = %{"host" => "server1", "compressr_index" => "main"}

      result = Schema.merge(schema, event)

      assert Map.has_key?(result, "host")
      refute Map.has_key?(result, "compressr_index")
    end
  end

  describe "fingerprint/1" do
    test "same structure produces same fingerprint" do
      event1 = %{"host" => "server1", "level" => "info", "_time" => 1}
      event2 = %{"host" => "server2", "level" => "error", "_time" => 2}

      assert Schema.fingerprint(event1) == Schema.fingerprint(event2)
    end

    test "different structure produces different fingerprint" do
      event1 = %{"host" => "server1", "level" => "info"}
      event2 = %{"host" => "server1", "level" => "info", "extra_field" => "value"}

      refute Schema.fingerprint(event1) == Schema.fingerprint(event2)
    end

    test "fingerprint ignores internal fields" do
      event1 = %{"host" => "server1", "_time" => 1}
      event2 = %{"host" => "server1", "_time" => 2, "_raw" => "data"}

      assert Schema.fingerprint(event1) == Schema.fingerprint(event2)
    end

    test "fingerprint is order-independent" do
      event1 = %{"a" => 1, "b" => 2, "c" => 3}
      event2 = %{"c" => 3, "a" => 1, "b" => 2}

      assert Schema.fingerprint(event1) == Schema.fingerprint(event2)
    end
  end

  describe "schema_fingerprint/1" do
    test "matches event fingerprint for same fields" do
      event = %{"host" => "server1", "level" => "info"}
      schema = Schema.merge(Schema.new(), event)

      assert Schema.schema_fingerprint(schema) == Schema.fingerprint(event)
    end
  end

  describe "compare/2" do
    setup do
      schema =
        Schema.new()
        |> Schema.merge(%{"host" => "server1", "level" => "info", "count" => 42})

      {:ok, schema: schema}
    end

    test "detects new fields", %{schema: schema} do
      event = %{"host" => "server1", "level" => "info", "count" => 42, "extra" => "new"}
      drifts = Schema.compare(schema, event)

      assert {:new_field, "extra", "new"} in drifts
    end

    test "detects missing fields", %{schema: schema} do
      event = %{"host" => "server1"}
      drifts = Schema.compare(schema, event)

      missing = Enum.filter(drifts, fn {type, _, _} -> type == :missing_field end)
      missing_fields = Enum.map(missing, fn {_, field, _} -> field end)

      assert "level" in missing_fields
      assert "count" in missing_fields
    end

    test "detects type changes", %{schema: schema} do
      event = %{"host" => "server1", "level" => "info", "count" => "not_a_number"}
      drifts = Schema.compare(schema, event)

      assert {:type_change, "count", {:integer, :string}} in drifts
    end

    test "does not flag nil values as type changes", %{schema: schema} do
      event = %{"host" => "server1", "level" => "info", "count" => nil}
      drifts = Schema.compare(schema, event)

      type_changes = Enum.filter(drifts, fn {type, _, _} -> type == :type_change end)
      assert type_changes == []
    end

    test "returns empty list when no drift", %{schema: schema} do
      event = %{"host" => "server2", "level" => "error", "count" => 100}
      drifts = Schema.compare(schema, event)

      assert drifts == []
    end

    test "detects multiple drift types at once", %{schema: schema} do
      event = %{"host" => 123, "new_field" => "value"}
      drifts = Schema.compare(schema, event)

      drift_types = Enum.map(drifts, fn {type, _, _} -> type end)

      assert :type_change in drift_types
      assert :new_field in drift_types
      assert :missing_field in drift_types
    end
  end

  describe "user_fields/1" do
    test "excludes internal fields starting with underscore" do
      event = %{"host" => "server1", "_time" => 123, "_raw" => "data", "__internal" => true}
      result = Schema.user_fields(event)

      assert result == %{"host" => "server1"}
    end

    test "excludes system fields starting with compressr_" do
      event = %{"host" => "server1", "compressr_index" => "main"}
      result = Schema.user_fields(event)

      assert result == %{"host" => "server1"}
    end
  end
end
