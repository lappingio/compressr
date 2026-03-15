defmodule Compressr.Source.HECTest do
  use ExUnit.Case, async: true

  alias Compressr.Source.HEC

  describe "validate_config/1" do
    test "valid config with port" do
      assert :ok = HEC.validate_config(%{"port" => 8088})
    end

    test "valid config with port and token" do
      assert :ok = HEC.validate_config(%{"port" => 8088, "token" => "my-token"})
    end

    test "rejects missing port" do
      assert {:error, {:missing_fields, ["port"]}} = HEC.validate_config(%{})
    end

    test "rejects non-integer port" do
      assert {:error, {:missing_fields, ["port"]}} =
               HEC.validate_config(%{"port" => "8088"})
    end
  end

  describe "handle_json_event/2" do
    setup do
      {:ok, state} = HEC.init(%{"port" => 8088})
      {:ok, state: state}
    end

    test "accepts valid HEC JSON event", %{state: state} do
      body = Jason.encode!(%{"event" => "Hello world"})

      assert {:ok, [event], _state} = HEC.handle_json_event(body, state)
      assert event["_raw"] == "Hello world"
      assert event["_time"] != nil
    end

    test "accepts JSON object as event", %{state: state} do
      body = Jason.encode!(%{"event" => %{"action" => "login", "user" => "admin"}})

      assert {:ok, [event], _state} = HEC.handle_json_event(body, state)
      assert is_binary(event["_raw"])
      # The raw should be the JSON-encoded event data
      assert {:ok, parsed} = Jason.decode(event["_raw"])
      assert parsed["action"] == "login"
    end

    test "preserves time from payload", %{state: state} do
      body = Jason.encode!(%{"event" => "test", "time" => 1_609_459_200})

      assert {:ok, [event], _state} = HEC.handle_json_event(body, state)
      assert event["_time"] == 1_609_459_200
    end

    test "preserves host, source, sourcetype, index from payload", %{state: state} do
      body =
        Jason.encode!(%{
          "event" => "test",
          "host" => "webserver01",
          "source" => "/var/log/app.log",
          "sourcetype" => "app:json",
          "index" => "main"
        })

      assert {:ok, [event], _state} = HEC.handle_json_event(body, state)
      assert event["host"] == "webserver01"
      assert event["source"] == "/var/log/app.log"
      assert event["sourcetype"] == "app:json"
      assert event["index"] == "main"
    end

    test "rejects invalid JSON", %{state: state} do
      assert {:error, _reason} = HEC.handle_json_event("not json", state)
    end

    test "rejects JSON without event field", %{state: state} do
      body = Jason.encode!(%{"data" => "no event key"})

      assert {:error, :invalid_hec_payload} = HEC.handle_json_event(body, state)
    end
  end

  describe "handle_raw_event/2" do
    setup do
      {:ok, state} = HEC.init(%{"port" => 8088})
      {:ok, state: state}
    end

    test "creates one event per line", %{state: state} do
      body = "Line one\nLine two\nLine three"

      assert {:ok, events, _state} = HEC.handle_raw_event(body, state)
      assert length(events) == 3
      assert Enum.at(events, 0)["_raw"] == "Line one"
      assert Enum.at(events, 1)["_raw"] == "Line two"
      assert Enum.at(events, 2)["_raw"] == "Line three"
    end

    test "handles single line without newline", %{state: state} do
      assert {:ok, [event], _state} = HEC.handle_raw_event("single line", state)
      assert event["_raw"] == "single line"
    end

    test "skips empty lines", %{state: state} do
      body = "line one\n\nline two\n"

      assert {:ok, events, _state} = HEC.handle_raw_event(body, state)
      assert length(events) == 2
    end
  end

  describe "authenticate/2" do
    test "allows any request when no token configured" do
      state = %{token: nil}
      assert :ok = HEC.authenticate("any-token", state)
      assert :ok = HEC.authenticate(nil, state)
    end

    test "allows any request when token is empty string" do
      state = %{token: ""}
      assert :ok = HEC.authenticate("any-token", state)
    end

    test "accepts matching token" do
      state = %{token: "my-secret-token"}
      assert :ok = HEC.authenticate("my-secret-token", state)
    end

    test "accepts token with Splunk prefix" do
      state = %{token: "my-secret-token"}
      assert :ok = HEC.authenticate("Splunk my-secret-token", state)
    end

    test "rejects invalid token" do
      state = %{token: "my-secret-token"}
      assert {:error, :unauthorized} = HEC.authenticate("wrong-token", state)
    end

    test "rejects nil token when auth required" do
      state = %{token: "my-secret-token"}
      assert {:error, :unauthorized} = HEC.authenticate(nil, state)
    end

    test "rejects empty token when auth required" do
      state = %{token: "my-secret-token"}
      assert {:error, :unauthorized} = HEC.authenticate("", state)
    end

    test "rejects wrong Splunk-prefixed token" do
      state = %{token: "my-secret-token"}
      assert {:error, :unauthorized} = HEC.authenticate("Splunk wrong-token", state)
    end
  end

  describe "success_response/0 and error_response/2" do
    test "success response has correct format" do
      resp = HEC.success_response()
      assert resp == %{"text" => "Success", "code" => 0}
    end

    test "error response has correct format" do
      resp = HEC.error_response(6, "Invalid data format")
      assert resp == %{"text" => "Invalid data format", "code" => 6}
    end
  end

  describe "init/1 and stop/1" do
    test "init stores config" do
      config = %{"port" => 8088, "token" => "abc123"}
      assert {:ok, state} = HEC.init(config)
      assert state.port == 8088
      assert state.token == "abc123"
    end

    test "init with no token" do
      config = %{"port" => 8088}
      assert {:ok, state} = HEC.init(config)
      assert state.token == nil
    end

    test "stop returns ok" do
      {:ok, state} = HEC.init(%{"port" => 8088})
      assert :ok = HEC.stop(state)
    end
  end

  describe "handle_data/2" do
    test "delegates to JSON parsing for valid JSON" do
      {:ok, state} = HEC.init(%{"port" => 8088})
      body = Jason.encode!(%{"event" => "test event"})

      assert {:ok, [event], _state} = HEC.handle_data(body, state)
      assert event["_raw"] == "test event"
    end

    test "falls back to raw parsing for non-JSON" do
      {:ok, state} = HEC.init(%{"port" => 8088})

      assert {:ok, [event], _state} = HEC.handle_data("raw text line", state)
      assert event["_raw"] == "raw text line"
    end
  end
end
