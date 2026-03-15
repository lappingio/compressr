defmodule Compressr.EventTest do
  use ExUnit.Case, async: true

  alias Compressr.Event
  alias Compressr.Event.Field

  # ── Construction ──────────────────────────────────────────────────

  describe "new/0 and new/1 (map)" do
    test "creates event with defaults" do
      event = Event.new()
      assert event["_raw"] == ""
      assert is_integer(event["_time"])
    end

    test "creates event from map preserving user fields" do
      event = Event.new(%{"_raw" => "hello", "host" => "web1"})
      assert event["_raw"] == "hello"
      assert event["host"] == "web1"
      assert is_integer(event["_time"])
    end

    test "respects explicit _time" do
      event = Event.new(%{"_raw" => "x", "_time" => 1_000_000})
      assert event["_time"] == 1_000_000
    end

    test "creates event from empty map" do
      event = Event.new(%{})
      assert event["_raw"] == ""
      assert is_integer(event["_time"])
    end
  end

  describe "new/2 (raw string + opts)" do
    test "creates event from raw string with keyword opts" do
      event = Event.new("raw data", _time: 42)
      assert event["_raw"] == "raw data"
      assert event["_time"] == 42
    end

    test "creates event from raw string with map opts" do
      event = Event.new("raw data", %{"host" => "web1"})
      assert event["_raw"] == "raw data"
      assert event["host"] == "web1"
      assert is_integer(event["_time"])
    end

    test "creates event from raw string with empty opts" do
      event = Event.new("raw data", [])
      assert event["_raw"] == "raw data"
      assert is_integer(event["_time"])
    end
  end

  describe "from_json/1" do
    test "parses valid JSON object" do
      json = ~s({"host":"web1","level":"info"})
      assert {:ok, event} = Event.from_json(json)
      assert event["host"] == "web1"
      assert event["level"] == "info"
      assert event["_raw"] == json
      assert is_integer(event["_time"])
    end

    test "preserves _time from JSON if present" do
      json = ~s({"_time":999})
      assert {:ok, event} = Event.from_json(json)
      assert event["_time"] == 999
    end

    test "returns error for invalid JSON" do
      assert {:error, %Jason.DecodeError{}} = Event.from_json("not json {{{")
    end

    test "returns error for JSON array (not object)" do
      assert {:error, :not_a_json_object} = Event.from_json("[1,2,3]")
    end

    test "returns error for JSON scalar" do
      assert {:error, :not_a_json_object} = Event.from_json(~s("just a string"))
    end

    test "handles JSON with nested objects" do
      json = ~s({"data":{"nested":true},"count":42})
      assert {:ok, event} = Event.from_json(json)
      assert event["data"] == %{"nested" => true}
      assert event["count"] == 42
    end

    test "handles JSON with null values" do
      json = ~s({"key":null})
      assert {:ok, event} = Event.from_json(json)
      assert event["key"] == nil
      assert Map.has_key?(event, "key")
    end

    test "handles JSON with special characters in field names" do
      json = ~s({"field.with.dots":"v1","field-with-dashes":"v2","field with spaces":"v3"})
      assert {:ok, event} = Event.from_json(json)
      assert event["field.with.dots"] == "v1"
      assert event["field-with-dashes"] == "v2"
      assert event["field with spaces"] == "v3"
    end

    test "handles empty JSON object" do
      json = ~s({})
      assert {:ok, event} = Event.from_json(json)
      assert event["_raw"] == json
      assert is_integer(event["_time"])
    end
  end

  describe "from_raw/1" do
    test "creates event from raw string" do
      event = Event.from_raw("syslog line")
      assert event["_raw"] == "syslog line"
      assert is_integer(event["_time"])
    end

    test "creates event from empty string" do
      event = Event.from_raw("")
      assert event["_raw"] == ""
    end

    test "creates event from string with special characters" do
      raw = "line with\nnewlines\tand\ttabs"
      event = Event.from_raw(raw)
      assert event["_raw"] == raw
    end
  end

  # ── Field Access ──────────────────────────────────────────────────

  describe "put_field/3" do
    test "sets a user field" do
      event = Event.new() |> Event.put_field("host", "web1")
      assert event["host"] == "web1"
    end

    test "overwrites an existing user field" do
      event =
        Event.new()
        |> Event.put_field("host", "web1")
        |> Event.put_field("host", "web2")

      assert event["host"] == "web2"
    end

    test "refuses to set internal (__) fields" do
      event = Event.new() |> Event.put_field("__input_id", "src1")
      refute Map.has_key?(event, "__input_id")
    end

    test "refuses to set system (compressr_) fields" do
      event = Event.new() |> Event.put_field("compressr_pipe", "main")
      refute Map.has_key?(event, "compressr_pipe")
    end

    test "allows setting _raw and _time (user-level standard fields)" do
      event =
        Event.new()
        |> Event.put_field("_raw", "updated")
        |> Event.put_field("_time", 123)

      assert event["_raw"] == "updated"
      assert event["_time"] == 123
    end

    test "sets field with nil value" do
      event = Event.new() |> Event.put_field("key", nil)
      assert Map.has_key?(event, "key")
      assert event["key"] == nil
    end

    test "sets field with complex value" do
      event = Event.new() |> Event.put_field("meta", %{"nested" => [1, 2, 3]})
      assert event["meta"] == %{"nested" => [1, 2, 3]}
    end
  end

  describe "get_field/2" do
    test "gets an existing field" do
      event = Event.new(%{"_raw" => "data", "host" => "web1"})
      assert Event.get_field(event, "host") == "web1"
    end

    test "returns nil for missing field" do
      event = Event.new()
      assert Event.get_field(event, "nonexistent") == nil
    end

    test "can read internal fields" do
      event = Event.new() |> Event.put_internal("__input_id", "src1")
      assert Event.get_field(event, "__input_id") == "src1"
    end

    test "can read system fields" do
      event = Event.new() |> Event.put_system("compressr_pipe", "main")
      assert Event.get_field(event, "compressr_pipe") == "main"
    end
  end

  describe "delete_field/2" do
    test "deletes a user field" do
      event = Event.new(%{"host" => "web1"}) |> Event.delete_field("host")
      refute Map.has_key?(event, "host")
    end

    test "refuses to delete internal fields" do
      event = Event.new() |> Event.put_internal("__input_id", "src1")
      result = Event.delete_field(event, "__input_id")
      assert result["__input_id"] == "src1"
    end

    test "refuses to delete system fields" do
      event = Event.new() |> Event.put_system("compressr_pipe", "main")
      result = Event.delete_field(event, "compressr_pipe")
      assert result["compressr_pipe"] == "main"
    end

    test "is a no-op for nonexistent fields" do
      event = Event.new()
      assert Event.delete_field(event, "nope") == event
    end
  end

  # ── Internal and System Fields ────────────────────────────────────

  describe "put_internal/3" do
    test "sets an internal field" do
      event = Event.new() |> Event.put_internal("__input_id", "src1")
      assert event["__input_id"] == "src1"
    end

    test "overwrites an existing internal field" do
      event =
        Event.new()
        |> Event.put_internal("__input_id", "src1")
        |> Event.put_internal("__input_id", "src2")

      assert event["__input_id"] == "src2"
    end
  end

  describe "put_system/3" do
    test "sets a system field" do
      event = Event.new() |> Event.put_system("compressr_host", "node1")
      assert event["compressr_host"] == "node1"
    end

    test "overwrites an existing system field" do
      event =
        Event.new()
        |> Event.put_system("compressr_host", "node1")
        |> Event.put_system("compressr_host", "node2")

      assert event["compressr_host"] == "node2"
    end
  end

  # ── Serialization ─────────────────────────────────────────────────

  describe "to_external_map/1" do
    test "strips internal fields" do
      event =
        Event.new(%{"_raw" => "data", "host" => "web1"})
        |> Event.put_internal("__input_id", "src1")
        |> Event.put_internal("__pipeline", "main")

      external = Event.to_external_map(event)

      refute Map.has_key?(external, "__input_id")
      refute Map.has_key?(external, "__pipeline")
      assert external["_raw"] == "data"
      assert external["host"] == "web1"
    end

    test "preserves system fields" do
      event =
        Event.new()
        |> Event.put_system("compressr_pipe", "main")
        |> Event.put_system("compressr_host", "node1")

      external = Event.to_external_map(event)

      assert external["compressr_pipe"] == "main"
      assert external["compressr_host"] == "node1"
    end

    test "preserves user fields" do
      event = Event.new(%{"_raw" => "x", "host" => "web1", "level" => "info"})
      external = Event.to_external_map(event)

      assert external["host"] == "web1"
      assert external["level"] == "info"
    end

    test "works on event with no internal fields" do
      event = Event.new(%{"_raw" => "hello"})
      assert Event.to_external_map(event) == event
    end
  end

  describe "to_json/1" do
    test "serializes event to JSON excluding internal fields" do
      event =
        Event.new(%{"_raw" => "data", "_time" => 100, "host" => "web1"})
        |> Event.put_internal("__input_id", "src1")

      assert {:ok, json} = Event.to_json(event)
      decoded = Jason.decode!(json)

      assert decoded["_raw"] == "data"
      assert decoded["_time"] == 100
      assert decoded["host"] == "web1"
      refute Map.has_key?(decoded, "__input_id")
    end

    test "includes system fields in JSON output" do
      event =
        Event.new(%{"_raw" => "data", "_time" => 100})
        |> Event.put_system("compressr_pipe", "main")

      assert {:ok, json} = Event.to_json(event)
      decoded = Jason.decode!(json)

      assert decoded["compressr_pipe"] == "main"
    end

    test "preserves field types through JSON" do
      event =
        Event.new(%{
          "_raw" => "data",
          "_time" => 100,
          "string_field" => "hello",
          "int_field" => 42,
          "float_field" => 3.14,
          "bool_field" => true,
          "null_field" => nil,
          "nested" => %{"a" => 1},
          "list_field" => [1, "two", 3]
        })

      assert {:ok, json} = Event.to_json(event)
      decoded = Jason.decode!(json)

      assert decoded["string_field"] == "hello"
      assert decoded["int_field"] == 42
      assert decoded["float_field"] == 3.14
      assert decoded["bool_field"] == true
      assert decoded["null_field"] == nil
      assert decoded["nested"] == %{"a" => 1}
      assert decoded["list_field"] == [1, "two", 3]
    end
  end

  # ── JSON Round-Trip ───────────────────────────────────────────────

  describe "JSON round-trip" do
    test "from_json -> to_json preserves user and system fields" do
      original_json = ~s({"host":"web1","level":"info","count":42})
      assert {:ok, event} = Event.from_json(original_json)

      event = Event.put_system(event, "compressr_pipe", "main")

      assert {:ok, output_json} = Event.to_json(event)
      decoded = Jason.decode!(output_json)

      assert decoded["host"] == "web1"
      assert decoded["level"] == "info"
      assert decoded["count"] == 42
      assert decoded["compressr_pipe"] == "main"
      assert decoded["_raw"] == original_json
    end

    test "from_json -> add internal -> to_json strips internal" do
      assert {:ok, event} = Event.from_json(~s({"msg":"hello"}))
      event = Event.put_internal(event, "__routing_key", "fast")

      assert {:ok, json} = Event.to_json(event)
      decoded = Jason.decode!(json)

      assert decoded["msg"] == "hello"
      refute Map.has_key?(decoded, "__routing_key")
    end
  end

  # ── Field Classification ──────────────────────────────────────────

  describe "Field.internal_field?/1" do
    test "detects __ prefixed fields" do
      assert Field.internal_field?("__input_id")
      assert Field.internal_field?("__pipeline")
      assert Field.internal_field?("__")
    end

    test "rejects non-internal fields" do
      refute Field.internal_field?("_raw")
      refute Field.internal_field?("_time")
      refute Field.internal_field?("host")
      refute Field.internal_field?("compressr_pipe")
      refute Field.internal_field?("")
    end
  end

  describe "Field.system_field?/1" do
    test "detects compressr_ prefixed fields" do
      assert Field.system_field?("compressr_pipe")
      assert Field.system_field?("compressr_host")
      assert Field.system_field?("compressr_input")
      assert Field.system_field?("compressr_output")
    end

    test "rejects non-system fields" do
      refute Field.system_field?("_raw")
      refute Field.system_field?("host")
      refute Field.system_field?("__input_id")
      refute Field.system_field?("")
    end
  end

  describe "Field.user_field?/1" do
    test "detects user fields" do
      assert Field.user_field?("host")
      assert Field.user_field?("_raw")
      assert Field.user_field?("_time")
      assert Field.user_field?("level")
      assert Field.user_field?("my_field")
    end

    test "rejects internal and system fields" do
      refute Field.user_field?("__input_id")
      refute Field.user_field?("compressr_pipe")
    end
  end

  describe "Field.strip_internal_fields/1" do
    test "removes all __ prefixed fields" do
      map = %{"_raw" => "x", "__a" => 1, "__b" => 2, "host" => "web1"}
      result = Field.strip_internal_fields(map)

      assert result == %{"_raw" => "x", "host" => "web1"}
    end

    test "returns unchanged map with no internal fields" do
      map = %{"_raw" => "x", "host" => "web1"}
      assert Field.strip_internal_fields(map) == map
    end

    test "handles empty map" do
      assert Field.strip_internal_fields(%{}) == %{}
    end
  end

  describe "Field.strip_system_fields/1" do
    test "removes all compressr_ prefixed fields" do
      map = %{"_raw" => "x", "compressr_pipe" => "main", "host" => "web1"}
      result = Field.strip_system_fields(map)

      assert result == %{"_raw" => "x", "host" => "web1"}
    end

    test "returns unchanged map with no system fields" do
      map = %{"_raw" => "x", "host" => "web1"}
      assert Field.strip_system_fields(map) == map
    end

    test "handles empty map" do
      assert Field.strip_system_fields(%{}) == %{}
    end
  end

  # ── Edge Cases ────────────────────────────────────────────────────

  describe "edge cases" do
    test "event with many field types coexisting" do
      event =
        Event.new(%{"_raw" => "data", "_time" => 100})
        |> Event.put_field("user_field", "val")
        |> Event.put_internal("__meta", "routing")
        |> Event.put_system("compressr_pipe", "main")

      assert event["user_field"] == "val"
      assert event["__meta"] == "routing"
      assert event["compressr_pipe"] == "main"

      external = Event.to_external_map(event)
      assert external["user_field"] == "val"
      assert external["compressr_pipe"] == "main"
      refute Map.has_key?(external, "__meta")
    end

    test "field names with special characters" do
      event =
        Event.new()
        |> Event.put_field("field.with.dots", "v1")
        |> Event.put_field("field-with-dashes", "v2")
        |> Event.put_field("field with spaces", "v3")
        |> Event.put_field("field/with/slashes", "v4")

      assert event["field.with.dots"] == "v1"
      assert event["field-with-dashes"] == "v2"
      assert event["field with spaces"] == "v3"
      assert event["field/with/slashes"] == "v4"
    end

    test "nested map values" do
      event = Event.put_field(Event.new(), "data", %{"deep" => %{"deeper" => true}})
      assert event["data"]["deep"]["deeper"] == true
    end

    test "unicode field names and values" do
      event =
        Event.new()
        |> Event.put_field("日本語", "テスト")

      assert event["日本語"] == "テスト"
    end

    test "large _raw string" do
      big = String.duplicate("x", 100_000)
      event = Event.from_raw(big)
      assert byte_size(event["_raw"]) == 100_000
    end

    test "from_json with empty string returns error" do
      assert {:error, %Jason.DecodeError{}} = Event.from_json("")
    end

    test "from_json with whitespace-only string returns error" do
      assert {:error, %Jason.DecodeError{}} = Event.from_json("   ")
    end
  end
end
