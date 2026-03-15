defmodule Compressr.Pipeline.Functions.RegexExtractTest do
  use ExUnit.Case, async: true

  alias Compressr.Event
  alias Compressr.Pipeline.Functions.RegexExtract

  defp make_event(fields \\ %{}) do
    Event.new(Map.merge(%{"_raw" => "test data", "host" => "web1"}, fields))
  end

  describe "execute/2 basic extraction" do
    test "extracts named capture groups from _raw" do
      event = make_event(%{"_raw" => "server.example.com:8080"})

      config = %{regex: ~r/(?<host>[\w.]+):(?<port>\d+)/}

      assert {:ok, result} = RegexExtract.execute(event, config)
      assert Event.get_field(result, "host") == "server.example.com"
      assert Event.get_field(result, "port") == "8080"
    end

    test "extracts from custom source field" do
      event = make_event(%{"message" => "user=admin action=login"})

      config = %{
        regex: ~r/user=(?<user>\w+)\s+action=(?<action>\w+)/,
        source_field: "message"
      }

      assert {:ok, result} = RegexExtract.execute(event, config)
      assert Event.get_field(result, "user") == "admin"
      assert Event.get_field(result, "action") == "login"
    end

    test "extracts single capture group" do
      event = make_event(%{"_raw" => "status=200"})

      config = %{regex: ~r/status=(?<status_code>\d+)/}

      assert {:ok, result} = RegexExtract.execute(event, config)
      assert Event.get_field(result, "status_code") == "200"
    end
  end

  describe "execute/2 no match" do
    test "leaves event unchanged when regex does not match" do
      event = make_event(%{"_raw" => "no match here"})

      config = %{regex: ~r/(?<host>[\w.]+):(?<port>\d+)/}

      assert {:ok, result} = RegexExtract.execute(event, config)
      assert Event.get_field(result, "host") == "web1"
      refute Map.has_key?(result, "port")
    end

    test "leaves event unchanged when source field is empty" do
      event = make_event(%{"_raw" => ""})

      config = %{regex: ~r/(?<key>\w+)/}

      assert {:ok, result} = RegexExtract.execute(event, config)
      assert result == event
    end
  end

  describe "execute/2 with string regex" do
    test "accepts string regex patterns" do
      event = make_event(%{"_raw" => "level=ERROR"})

      config = %{regex: "level=(?<level>\\w+)"}

      assert {:ok, result} = RegexExtract.execute(event, config)
      assert Event.get_field(result, "level") == "ERROR"
    end
  end

  describe "execute/2 edge cases" do
    test "non-string source field value is skipped" do
      event = make_event(%{"count" => 42})

      config = %{regex: ~r/(?<num>\d+)/, source_field: "count"}

      assert {:ok, result} = RegexExtract.execute(event, config)
      assert result == event
    end

    test "nil source field value is skipped" do
      event = make_event()

      config = %{regex: ~r/(?<key>\w+)/, source_field: "nonexistent"}

      assert {:ok, result} = RegexExtract.execute(event, config)
      assert result == event
    end

    test "overwrites existing fields with captures" do
      event = make_event(%{"_raw" => "host=new_host", "host" => "old_host"})

      config = %{regex: ~r/host=(?<host>\w+)/}

      assert {:ok, result} = RegexExtract.execute(event, config)
      assert Event.get_field(result, "host") == "new_host"
    end

    test "handles complex regex with multiple groups" do
      event =
        make_event(%{
          "_raw" => "2024-01-15T10:30:00Z INFO [web] Request from 192.168.1.1"
        })

      config = %{
        regex:
          ~r/(?<timestamp>\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z)\s+(?<log_level>\w+)\s+\[(?<component>\w+)\]\s+.*from\s+(?<client_ip>[\d.]+)/
      }

      assert {:ok, result} = RegexExtract.execute(event, config)
      assert Event.get_field(result, "timestamp") == "2024-01-15T10:30:00Z"
      assert Event.get_field(result, "log_level") == "INFO"
      assert Event.get_field(result, "component") == "web"
      assert Event.get_field(result, "client_ip") == "192.168.1.1"
    end

    test "returns error on missing regex in config" do
      event = make_event()
      assert {:error, _} = RegexExtract.execute(event, %{})
    end
  end
end
