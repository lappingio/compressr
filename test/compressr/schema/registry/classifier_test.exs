defmodule Compressr.Schema.Registry.ClassifierTest do
  use ExUnit.Case, async: true

  alias Compressr.Schema.Registry.Classifier

  describe "classify/1" do
    test "returns a fingerprint-based log type ID for an event" do
      event = %{"host" => "server1", "level" => "info", "_time" => 123}
      result = Classifier.classify(event)

      assert String.starts_with?(result, "fp_")
    end

    test "same field set produces same log type ID" do
      event1 = %{"host" => "server1", "level" => "info", "_time" => 1}
      event2 = %{"host" => "server2", "level" => "error", "_time" => 2}

      assert Classifier.classify(event1) == Classifier.classify(event2)
    end

    test "different field sets produce different log type IDs" do
      event1 = %{"host" => "server1", "level" => "info"}
      event2 = %{"host" => "server1", "level" => "info", "extra" => "field"}

      refute Classifier.classify(event1) == Classifier.classify(event2)
    end

    test "ignores internal fields when fingerprinting" do
      event1 = %{"host" => "server1", "_time" => 1}
      event2 = %{"host" => "server1", "_time" => 2, "_raw" => "data"}

      assert Classifier.classify(event1) == Classifier.classify(event2)
    end

    test "ignores system fields when fingerprinting" do
      event1 = %{"host" => "server1"}
      event2 = %{"host" => "server1", "compressr_index" => "main"}

      assert Classifier.classify(event1) == Classifier.classify(event2)
    end

    test "field order does not affect classification" do
      event1 = %{"a" => 1, "b" => 2, "c" => 3}
      event2 = %{"c" => 3, "a" => 1, "b" => 2}

      assert Classifier.classify(event1) == Classifier.classify(event2)
    end
  end

  describe "classify/2 with field presence rules" do
    test "field presence rule overrides fingerprint" do
      rules = [
        {:field_presence,
         %{fields: ["request_path", "status_code"], log_type_id: "http_access"}}
      ]

      event = %{
        "request_path" => "/api/health",
        "status_code" => 200,
        "method" => "GET",
        "_time" => 123
      }

      assert Classifier.classify(event, rules: rules) == "http_access"
    end

    test "field presence rule does not match when fields missing" do
      rules = [
        {:field_presence,
         %{fields: ["request_path", "status_code"], log_type_id: "http_access"}}
      ]

      event = %{"request_path" => "/api/health", "method" => "GET", "_time" => 123}

      # Should fall through to fingerprint
      result = Classifier.classify(event, rules: rules)
      assert String.starts_with?(result, "fp_")
      refute result == "http_access"
    end
  end

  describe "classify/2 with regex rules" do
    test "regex rule matches on _raw field" do
      rules = [
        {:regex, %{pattern: ~r/^<\d+>/, log_type_id: "syslog"}}
      ]

      event = %{"_raw" => "<134>Oct 11 22:14:15 server sshd: message", "_time" => 123}

      assert Classifier.classify(event, rules: rules) == "syslog"
    end

    test "regex rule does not match when pattern fails" do
      rules = [
        {:regex, %{pattern: ~r/^<\d+>/, log_type_id: "syslog"}}
      ]

      event = %{"_raw" => "normal log message", "host" => "server1", "_time" => 123}

      result = Classifier.classify(event, rules: rules)
      assert String.starts_with?(result, "fp_")
    end
  end

  describe "classify/2 with rule priority" do
    test "first matching rule wins" do
      rules = [
        {:field_presence,
         %{fields: ["request_path"], log_type_id: "http_access"}},
        {:regex, %{pattern: ~r/^<\d+>/, log_type_id: "syslog"}}
      ]

      # This event matches the field presence rule
      event = %{
        "request_path" => "/api",
        "_raw" => "<134>message",
        "_time" => 123
      }

      assert Classifier.classify(event, rules: rules) == "http_access"
    end
  end

  describe "classify_batch/1" do
    test "groups events by log type" do
      events = [
        %{"host" => "server1", "level" => "info"},
        %{"host" => "server2", "level" => "error"},
        %{"request_path" => "/api", "status_code" => 200},
        %{"request_path" => "/health", "status_code" => 200},
        %{"user" => "root", "action" => "login"}
      ]

      grouped = Classifier.classify_batch(events)

      # Should have 3 groups: host+level, request_path+status_code, user+action
      assert map_size(grouped) == 3

      # Each group should have the right count
      counts = grouped |> Map.values() |> Enum.map(&length/1) |> Enum.sort()
      assert counts == [1, 2, 2]
    end

    test "batch classification with rules" do
      rules = [
        {:field_presence,
         %{fields: ["request_path", "status_code"], log_type_id: "http_access"}}
      ]

      events = [
        %{"request_path" => "/api", "status_code" => 200},
        %{"request_path" => "/health", "status_code" => 200},
        %{"host" => "server1", "level" => "info"}
      ]

      grouped = Classifier.classify_batch(events, rules: rules)

      assert Map.has_key?(grouped, "http_access")
      assert length(grouped["http_access"]) == 2
    end
  end

  describe "fingerprint_id/1" do
    test "returns a hex string prefixed with fp_" do
      event = %{"host" => "server1", "level" => "info"}
      result = Classifier.fingerprint_id(event)

      assert String.starts_with?(result, "fp_")
      # fp_ + 64 hex chars (sha256)
      assert String.length(result) == 3 + 64
    end
  end
end
