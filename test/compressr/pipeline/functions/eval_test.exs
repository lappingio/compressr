defmodule Compressr.Pipeline.Functions.EvalTest do
  use ExUnit.Case, async: true

  alias Compressr.Event
  alias Compressr.Pipeline.Functions.Eval

  defp make_event(fields \\ %{}) do
    Event.new(Map.merge(%{"_raw" => "test data", "host" => "web1"}, fields))
  end

  describe "execute/2 adding fields" do
    test "adds a field with a static value via function" do
      event = make_event()
      config = %{fields: [{"severity", fn _e -> "high" end}]}

      assert {:ok, result} = Eval.execute(event, config)
      assert Event.get_field(result, "severity") == "high"
    end

    test "adds multiple fields" do
      event = make_event()

      config = %{
        fields: [
          {"field_a", fn _e -> "a" end},
          {"field_b", fn _e -> "b" end},
          {"field_c", fn _e -> "c" end}
        ]
      }

      assert {:ok, result} = Eval.execute(event, config)
      assert Event.get_field(result, "field_a") == "a"
      assert Event.get_field(result, "field_b") == "b"
      assert Event.get_field(result, "field_c") == "c"
    end

    test "adds field based on existing event data" do
      event = make_event(%{"host" => "web1"})

      config = %{
        fields: [{"upper_host", fn e -> String.upcase(Event.get_field(e, "host")) end}]
      }

      assert {:ok, result} = Eval.execute(event, config)
      assert Event.get_field(result, "upper_host") == "WEB1"
    end

    test "modifies an existing field" do
      event = make_event(%{"count" => "5"})

      config = %{
        fields: [{"count", fn e -> String.to_integer(Event.get_field(e, "count")) * 2 end}]
      }

      assert {:ok, result} = Eval.execute(event, config)
      assert Event.get_field(result, "count") == 10
    end

    test "chained field expressions can reference earlier additions" do
      event = make_event()

      config = %{
        fields: [
          {"step1", fn _e -> "hello" end},
          {"step2", fn e -> Event.get_field(e, "step1") <> " world" end}
        ]
      }

      assert {:ok, result} = Eval.execute(event, config)
      assert Event.get_field(result, "step2") == "hello world"
    end
  end

  describe "execute/2 with remove_fields" do
    test "removes a specific field" do
      event = make_event(%{"debug_info" => "verbose", "host" => "web1"})
      config = %{remove_fields: ["debug_info"]}

      assert {:ok, result} = Eval.execute(event, config)
      assert Event.get_field(result, "debug_info") == nil
      assert Event.get_field(result, "host") == "web1"
    end

    test "removes fields matching wildcard pattern" do
      event = make_event(%{"debug_info" => "x", "debug_trace" => "y", "host" => "web1"})
      config = %{remove_fields: ["debug_*"]}

      assert {:ok, result} = Eval.execute(event, config)
      assert Event.get_field(result, "debug_info") == nil
      assert Event.get_field(result, "debug_trace") == nil
      assert Event.get_field(result, "host") == "web1"
    end

    test "can remove _raw and _time via exact match" do
      event = make_event()
      config = %{remove_fields: ["_raw", "_time"]}

      assert {:ok, result} = Eval.execute(event, config)
      # _raw and _time are user fields, so delete_field allows removal
      assert Event.get_field(result, "_raw") == nil
      assert Event.get_field(result, "_time") == nil
    end

    test "removes multiple specific fields" do
      event = make_event(%{"a" => 1, "b" => 2, "c" => 3})
      config = %{remove_fields: ["a", "b"]}

      assert {:ok, result} = Eval.execute(event, config)
      assert Event.get_field(result, "a") == nil
      assert Event.get_field(result, "b") == nil
      assert Event.get_field(result, "c") == 3
    end

    test "no-op when removing nonexistent fields" do
      event = make_event()
      config = %{remove_fields: ["nonexistent"]}

      assert {:ok, result} = Eval.execute(event, config)
      assert result == event
    end
  end

  describe "execute/2 with keep_fields" do
    test "keeps only specified fields" do
      event = make_event(%{"a" => 1, "b" => 2, "c" => 3})
      config = %{keep_fields: ["a"]}

      assert {:ok, result} = Eval.execute(event, config)
      assert Event.get_field(result, "a") == 1
      assert Event.get_field(result, "b") == nil
      assert Event.get_field(result, "c") == nil
    end

    test "always preserves _raw and _time" do
      event = make_event(%{"a" => 1, "b" => 2})
      config = %{keep_fields: ["a"]}

      assert {:ok, result} = Eval.execute(event, config)
      assert Event.get_field(result, "_raw") != nil
      assert Event.get_field(result, "_time") != nil
      assert Event.get_field(result, "a") == 1
    end

    test "preserves internal and system fields" do
      event =
        make_event()
        |> Event.put_internal("__pipeline_id", "pipe1")
        |> Event.put_system("compressr_host", "node1")

      config = %{keep_fields: ["host"]}

      assert {:ok, result} = Eval.execute(event, config)
      assert Event.get_field(result, "host") == "web1"
      assert Event.get_field(result, "__pipeline_id") == "pipe1"
      assert Event.get_field(result, "compressr_host") == "node1"
    end

    test "keep_fields takes precedence over remove_fields" do
      event = make_event(%{"a" => 1, "b" => 2, "c" => 3})
      config = %{keep_fields: ["a", "b"], remove_fields: ["a"]}

      assert {:ok, result} = Eval.execute(event, config)
      # keep_fields takes precedence, so "a" is kept
      assert Event.get_field(result, "a") == 1
      assert Event.get_field(result, "b") == 2
      assert Event.get_field(result, "c") == nil
    end
  end

  describe "execute/2 with fields and remove/keep combined" do
    test "adds fields then applies remove" do
      event = make_event()

      config = %{
        fields: [{"new_field", fn _e -> "value" end}],
        remove_fields: ["host"]
      }

      assert {:ok, result} = Eval.execute(event, config)
      assert Event.get_field(result, "new_field") == "value"
      assert Event.get_field(result, "host") == nil
    end
  end

  describe "execute/2 edge cases" do
    test "empty config is a no-op" do
      event = make_event()
      assert {:ok, ^event} = Eval.execute(event, %{})
    end

    test "empty fields list is a no-op" do
      event = make_event()
      assert {:ok, ^event} = Eval.execute(event, %{fields: []})
    end

    test "empty remove_fields list is a no-op" do
      event = make_event()
      assert {:ok, ^event} = Eval.execute(event, %{remove_fields: []})
    end

    test "returns error on exception" do
      event = make_event()

      config = %{
        fields: [{"boom", fn _e -> raise "kaboom" end}]
      }

      assert {:error, "kaboom"} = Eval.execute(event, config)
    end
  end
end
