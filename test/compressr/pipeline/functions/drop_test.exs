defmodule Compressr.Pipeline.Functions.DropTest do
  use ExUnit.Case, async: true

  alias Compressr.Event
  alias Compressr.Pipeline
  alias Compressr.Pipeline.Function, as: PipelineFunction
  alias Compressr.Pipeline.Functions.Drop

  defp make_event(fields \\ %{}) do
    Event.new(Map.merge(%{"_raw" => "test data", "host" => "web1"}, fields))
  end

  describe "execute/2" do
    test "always returns drop" do
      event = make_event()
      assert {:drop, "matched drop filter"} = Drop.execute(event, %{})
    end

    test "returns drop regardless of event content" do
      event = make_event(%{"any" => "field", "level" => "critical"})
      assert {:drop, "matched drop filter"} = Drop.execute(event, %{})
    end

    test "returns drop with any config" do
      event = make_event()
      assert {:drop, "matched drop filter"} = Drop.execute(event, %{some: "config"})
    end
  end

  describe "drop in pipeline with filter" do
    test "drops events matching the filter" do
      pipeline = %Pipeline{
        functions: [
          %PipelineFunction{
            module: Drop,
            config: %{},
            filter: fn e -> Event.get_field(e, "level") == "debug" end
          }
        ]
      }

      debug_event = make_event(%{"level" => "debug"})
      assert {:drop, "matched drop filter"} = Pipeline.execute(pipeline, debug_event)
    end

    test "passes through events not matching the filter" do
      pipeline = %Pipeline{
        functions: [
          %PipelineFunction{
            module: Drop,
            config: %{},
            filter: fn e -> Event.get_field(e, "level") == "debug" end
          }
        ]
      }

      info_event = make_event(%{"level" => "info"})
      assert {:ok, ^info_event} = Pipeline.execute(pipeline, info_event)
    end

    test "drop prevents downstream functions from executing" do
      pipeline = %Pipeline{
        functions: [
          %PipelineFunction{
            module: Drop,
            config: %{}
          },
          %PipelineFunction{
            module: Compressr.Pipeline.Functions.Eval,
            config: %{fields: [{"should_not_appear", fn _e -> true end}]}
          }
        ]
      }

      event = make_event()
      assert {:drop, _} = Pipeline.execute(pipeline, event)
    end
  end
end
