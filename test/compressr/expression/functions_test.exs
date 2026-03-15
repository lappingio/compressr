defmodule Compressr.Expression.FunctionsTest do
  use ExUnit.Case, async: true

  alias Compressr.Expression.Functions

  describe "exists/2" do
    test "returns true for existing non-nil field" do
      assert Functions.exists(%{"name" => "alice"}, ["name"])
    end

    test "returns false for missing field" do
      refute Functions.exists(%{"name" => "alice"}, ["age"])
    end

    test "returns false for nil field" do
      refute Functions.exists(%{"name" => nil}, ["name"])
    end

    test "works with nested fields" do
      event = %{"request" => %{"path" => "/api"}}
      assert Functions.exists(event, ["request", "path"])
    end

    test "returns false for partially missing nested path" do
      event = %{"request" => %{"path" => "/api"}}
      refute Functions.exists(event, ["request", "method"])
    end

    test "returns false when intermediate is not a map" do
      event = %{"request" => "string_value"}
      refute Functions.exists(event, ["request", "path"])
    end
  end

  describe "length/1" do
    test "string length" do
      assert Functions.length("hello") == 5
    end

    test "empty string" do
      assert Functions.length("") == 0
    end

    test "unicode string length" do
      assert Functions.length("cafe\u0301") == 4
    end

    test "list length" do
      assert Functions.length([1, 2, 3]) == 3
    end

    test "empty list" do
      assert Functions.length([]) == 0
    end

    test "map size" do
      assert Functions.length(%{"a" => 1, "b" => 2}) == 2
    end

    test "nil returns 0" do
      assert Functions.length(nil) == 0
    end
  end

  describe "downcase/1" do
    test "lowercases a string" do
      assert Functions.downcase("HELLO") == "hello"
    end

    test "mixed case" do
      assert Functions.downcase("Hello World") == "hello world"
    end

    test "nil returns nil" do
      assert Functions.downcase(nil) == nil
    end
  end

  describe "upcase/1" do
    test "uppercases a string" do
      assert Functions.upcase("hello") == "HELLO"
    end

    test "nil returns nil" do
      assert Functions.upcase(nil) == nil
    end
  end

  describe "to_int/1" do
    test "integer passthrough" do
      assert Functions.to_int(42) == 42
    end

    test "float truncation" do
      assert Functions.to_int(3.7) == 3
    end

    test "string parsing" do
      assert Functions.to_int("42") == 42
    end

    test "string with trailing chars" do
      assert Functions.to_int("42abc") == 42
    end

    test "non-numeric string" do
      assert Functions.to_int("hello") == nil
    end

    test "boolean true" do
      assert Functions.to_int(true) == 1
    end

    test "boolean false" do
      assert Functions.to_int(false) == 0
    end

    test "nil returns nil" do
      assert Functions.to_int(nil) == nil
    end
  end

  describe "to_float/1" do
    test "float passthrough" do
      assert Functions.to_float(3.14) == 3.14
    end

    test "integer to float" do
      assert Functions.to_float(42) == 42.0
    end

    test "string parsing" do
      assert Functions.to_float("3.14") == 3.14
    end

    test "non-numeric string" do
      assert Functions.to_float("hello") == nil
    end

    test "nil returns nil" do
      assert Functions.to_float(nil) == nil
    end
  end

  describe "to_string/1" do
    test "string passthrough" do
      assert Functions.to_string("hello") == "hello"
    end

    test "integer to string" do
      assert Functions.to_string(42) == "42"
    end

    test "float to string" do
      result = Functions.to_string(3.14)
      assert is_binary(result)
      assert String.contains?(result, "3.14")
    end

    test "boolean true" do
      assert Functions.to_string(true) == "true"
    end

    test "boolean false" do
      assert Functions.to_string(false) == "false"
    end

    test "nil returns empty string" do
      assert Functions.to_string(nil) == ""
    end
  end

  describe "now/0" do
    test "returns a unix timestamp" do
      ts = Functions.now()
      assert is_integer(ts)
      # Should be after 2024
      assert ts > 1_700_000_000
    end
  end

  describe "contains/2" do
    test "substring present" do
      assert Functions.contains("hello world", "world")
    end

    test "substring absent" do
      refute Functions.contains("hello world", "xyz")
    end

    test "nil string" do
      refute Functions.contains(nil, "test")
    end

    test "empty substring" do
      assert Functions.contains("hello", "")
    end
  end

  describe "starts_with/2" do
    test "matching prefix" do
      assert Functions.starts_with("hello world", "hello")
    end

    test "non-matching prefix" do
      refute Functions.starts_with("hello world", "world")
    end

    test "nil string" do
      refute Functions.starts_with(nil, "test")
    end
  end

  describe "ends_with/2" do
    test "matching suffix" do
      assert Functions.ends_with("hello world", "world")
    end

    test "non-matching suffix" do
      refute Functions.ends_with("hello world", "hello")
    end

    test "nil string" do
      refute Functions.ends_with(nil, "test")
    end
  end

  describe "match/2" do
    test "matching regex" do
      assert Functions.match("error: something failed", "error")
    end

    test "non-matching regex" do
      refute Functions.match("info: all good", "error")
    end

    test "regex with special chars" do
      assert Functions.match("2024-01-15", "\\d{4}-\\d{2}-\\d{2}")
    end

    test "nil string" do
      refute Functions.match(nil, "test")
    end

    test "invalid regex returns false" do
      refute Functions.match("test", "[invalid")
    end
  end

  describe "get_nested/2" do
    test "top-level key" do
      assert Functions.get_nested(%{"a" => 1}, ["a"]) == 1
    end

    test "nested key" do
      assert Functions.get_nested(%{"a" => %{"b" => 2}}, ["a", "b"]) == 2
    end

    test "missing key" do
      assert Functions.get_nested(%{"a" => 1}, ["b"]) == :field_missing
    end

    test "empty path returns the map" do
      map = %{"a" => 1}
      assert Functions.get_nested(map, []) == map
    end
  end
end
