defmodule Compressr.Pipeline.Functions.MaskTest do
  use ExUnit.Case, async: true

  alias Compressr.Event
  alias Compressr.Pipeline.Functions.Mask

  defp make_event(fields \\ %{}) do
    Event.new(Map.merge(%{"_raw" => "test data", "host" => "web1"}, fields))
  end

  describe "execute/2 basic masking" do
    test "replaces regex pattern in _raw by default" do
      event = make_event(%{"_raw" => "card: 4111-1111-1111-1111"})

      config = %{
        rules: [%{regex: ~r/\d{4}-\d{4}-\d{4}-\d{4}/, replacement: "XXXX-XXXX-XXXX-XXXX"}]
      }

      assert {:ok, result} = Mask.execute(event, config)
      assert Event.get_field(result, "_raw") == "card: XXXX-XXXX-XXXX-XXXX"
    end

    test "replaces all occurrences of pattern" do
      event = make_event(%{"_raw" => "ssn: 123-45-6789, other ssn: 987-65-4321"})

      config = %{
        rules: [%{regex: ~r/\d{3}-\d{2}-\d{4}/, replacement: "XXX-XX-XXXX"}]
      }

      assert {:ok, result} = Mask.execute(event, config)
      assert Event.get_field(result, "_raw") == "ssn: XXX-XX-XXXX, other ssn: XXX-XX-XXXX"
    end

    test "masks specified fields instead of _raw" do
      event = make_event(%{"message" => "password is secret123", "_raw" => "unchanged"})

      config = %{
        rules: [%{regex: ~r/secret\d+/, replacement: "REDACTED"}],
        fields: ["message"]
      }

      assert {:ok, result} = Mask.execute(event, config)
      assert Event.get_field(result, "message") == "password is REDACTED"
      assert Event.get_field(result, "_raw") == "unchanged"
    end

    test "masks multiple fields" do
      event =
        make_event(%{
          "message" => "user: admin@test.com",
          "details" => "contact: user@example.com"
        })

      config = %{
        rules: [%{regex: ~r/[\w.]+@[\w.]+/, replacement: "[EMAIL]"}],
        fields: ["message", "details"]
      }

      assert {:ok, result} = Mask.execute(event, config)
      assert Event.get_field(result, "message") == "user: [EMAIL]"
      assert Event.get_field(result, "details") == "contact: [EMAIL]"
    end
  end

  describe "execute/2 multiple rules" do
    test "applies multiple rules in order" do
      event = make_event(%{"_raw" => "ssn: 123-45-6789, card: 4111111111111111"})

      config = %{
        rules: [
          %{regex: ~r/\d{3}-\d{2}-\d{4}/, replacement: "XXX-XX-XXXX"},
          %{regex: ~r/\d{16}/, replacement: "XXXXXXXXXXXXXXXX"}
        ]
      }

      assert {:ok, result} = Mask.execute(event, config)

      assert Event.get_field(result, "_raw") ==
               "ssn: XXX-XX-XXXX, card: XXXXXXXXXXXXXXXX"
    end

    test "second rule can match output of first rule" do
      event = make_event(%{"_raw" => "data: ABC"})

      config = %{
        rules: [
          %{regex: ~r/ABC/, replacement: "DEF"},
          %{regex: ~r/DEF/, replacement: "GHI"}
        ]
      }

      assert {:ok, result} = Mask.execute(event, config)
      assert Event.get_field(result, "_raw") == "data: GHI"
    end
  end

  describe "execute/2 disabled rules" do
    test "skips disabled rules" do
      event = make_event(%{"_raw" => "secret: ABC, other: DEF"})

      config = %{
        rules: [
          %{regex: ~r/ABC/, replacement: "XXX", enabled: false},
          %{regex: ~r/DEF/, replacement: "YYY", enabled: true}
        ]
      }

      assert {:ok, result} = Mask.execute(event, config)
      assert Event.get_field(result, "_raw") == "secret: ABC, other: YYY"
    end

    test "all rules disabled is a no-op" do
      event = make_event(%{"_raw" => "keep this"})

      config = %{
        rules: [
          %{regex: ~r/keep/, replacement: "drop", enabled: false}
        ]
      }

      assert {:ok, result} = Mask.execute(event, config)
      assert Event.get_field(result, "_raw") == "keep this"
    end
  end

  describe "execute/2 with string regex patterns" do
    test "accepts string regex patterns" do
      event = make_event(%{"_raw" => "password: abc123"})

      config = %{
        rules: [%{regex: "abc\\d+", replacement: "REDACTED"}]
      }

      assert {:ok, result} = Mask.execute(event, config)
      assert Event.get_field(result, "_raw") == "password: REDACTED"
    end
  end

  describe "execute/2 edge cases" do
    test "empty rules list is a no-op" do
      event = make_event()
      assert {:ok, ^event} = Mask.execute(event, %{rules: []})
    end

    test "empty config is a no-op" do
      event = make_event()
      assert {:ok, ^event} = Mask.execute(event, %{})
    end

    test "non-string field values are skipped" do
      event = make_event(%{"count" => 42})

      config = %{
        rules: [%{regex: ~r/\d+/, replacement: "X"}],
        fields: ["count"]
      }

      assert {:ok, result} = Mask.execute(event, config)
      assert Event.get_field(result, "count") == 42
    end

    test "nil field values are skipped" do
      event = make_event(%{"missing" => nil})

      config = %{
        rules: [%{regex: ~r/anything/, replacement: "X"}],
        fields: ["missing"]
      }

      assert {:ok, result} = Mask.execute(event, config)
      assert Event.get_field(result, "missing") == nil
    end

    test "nonexistent field is skipped" do
      event = make_event()

      config = %{
        rules: [%{regex: ~r/anything/, replacement: "X"}],
        fields: ["nonexistent"]
      }

      assert {:ok, result} = Mask.execute(event, config)
      assert result == event
    end

    test "no match leaves value unchanged" do
      event = make_event(%{"_raw" => "nothing to mask here"})

      config = %{
        rules: [%{regex: ~r/\d{16}/, replacement: "MASKED"}]
      }

      assert {:ok, result} = Mask.execute(event, config)
      assert Event.get_field(result, "_raw") == "nothing to mask here"
    end
  end
end
