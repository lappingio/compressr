defmodule Compressr.PipelineTest do
  use ExUnit.Case, async: true

  alias Compressr.Event
  alias Compressr.Pipeline
  alias Compressr.Pipeline.Function, as: PipelineFunction
  alias Compressr.Pipeline.Functions.{Comment, Drop, Eval, Mask, Rename}

  defp make_event(fields \\ %{}) do
    Event.new(Map.merge(%{"_raw" => "test data", "host" => "web1", "level" => "info"}, fields))
  end

  describe "execute/2 with empty pipeline" do
    test "passes event through unchanged" do
      pipeline = %Pipeline{functions: []}
      event = make_event()

      assert {:ok, ^event} = Pipeline.execute(pipeline, event)
    end
  end

  describe "execute/2 with disabled pipeline" do
    test "passes event through unchanged" do
      pipeline = %Pipeline{
        enabled: false,
        functions: [
          %PipelineFunction{
            module: Drop,
            config: %{}
          }
        ]
      }

      event = make_event()
      assert {:ok, ^event} = Pipeline.execute(pipeline, event)
    end
  end

  describe "execute/2 sequential execution" do
    test "executes functions in order" do
      pipeline = %Pipeline{
        functions: [
          %PipelineFunction{
            module: Eval,
            config: %{fields: [{"step1", fn _e -> "done" end}]}
          },
          %PipelineFunction{
            module: Eval,
            config: %{fields: [{"step2", fn e -> Event.get_field(e, "step1") <> "_chained" end}]}
          }
        ]
      }

      event = make_event()
      assert {:ok, result} = Pipeline.execute(pipeline, event)
      assert Event.get_field(result, "step1") == "done"
      assert Event.get_field(result, "step2") == "done_chained"
    end

    test "executes multiple functions on event" do
      pipeline = %Pipeline{
        functions: [
          %PipelineFunction{
            module: Eval,
            config: %{fields: [{"severity", fn _e -> "high" end}]}
          },
          %PipelineFunction{
            module: Rename,
            config: %{renames: %{"host" => "source_host"}}
          }
        ]
      }

      event = make_event()
      assert {:ok, result} = Pipeline.execute(pipeline, event)
      assert Event.get_field(result, "severity") == "high"
      assert Event.get_field(result, "source_host") == "web1"
      assert Event.get_field(result, "host") == nil
    end
  end

  describe "execute/2 with filter expressions" do
    test "function only runs on matching events" do
      pipeline = %Pipeline{
        functions: [
          %PipelineFunction{
            module: Eval,
            config: %{fields: [{"processed", fn _e -> true end}]},
            filter: fn event -> Event.get_field(event, "level") == "error" end
          }
        ]
      }

      info_event = make_event(%{"level" => "info"})
      assert {:ok, result} = Pipeline.execute(pipeline, info_event)
      assert Event.get_field(result, "processed") == nil

      error_event = make_event(%{"level" => "error"})
      assert {:ok, result} = Pipeline.execute(pipeline, error_event)
      assert Event.get_field(result, "processed") == true
    end

    test "non-matching events pass through unchanged" do
      pipeline = %Pipeline{
        functions: [
          %PipelineFunction{
            module: Eval,
            config: %{fields: [{"tag", fn _e -> "tagged" end}]},
            filter: fn event -> Event.get_field(event, "host") == "web99" end
          }
        ]
      }

      event = make_event()
      assert {:ok, result} = Pipeline.execute(pipeline, event)
      assert Event.get_field(result, "tag") == nil
      assert Event.get_field(result, "host") == "web1"
    end

    test "nil filter matches all events" do
      pipeline = %Pipeline{
        functions: [
          %PipelineFunction{
            module: Eval,
            config: %{fields: [{"processed", fn _e -> true end}]},
            filter: nil
          }
        ]
      }

      event = make_event()
      assert {:ok, result} = Pipeline.execute(pipeline, event)
      assert Event.get_field(result, "processed") == true
    end
  end

  describe "execute/2 with Final toggle" do
    test "stops downstream processing when final function matches" do
      pipeline = %Pipeline{
        functions: [
          %PipelineFunction{
            module: Eval,
            config: %{fields: [{"step1", fn _e -> "done" end}]},
            final: true
          },
          %PipelineFunction{
            module: Eval,
            config: %{fields: [{"step2", fn _e -> "done" end}]}
          }
        ]
      }

      event = make_event()
      assert {:ok, result} = Pipeline.execute(pipeline, event)
      assert Event.get_field(result, "step1") == "done"
      assert Event.get_field(result, "step2") == nil
    end

    test "final toggle does not affect non-matching events" do
      pipeline = %Pipeline{
        functions: [
          %PipelineFunction{
            module: Eval,
            config: %{fields: [{"step1", fn _e -> "done" end}]},
            final: true,
            filter: fn event -> Event.get_field(event, "level") == "error" end
          },
          %PipelineFunction{
            module: Eval,
            config: %{fields: [{"step2", fn _e -> "done" end}]}
          }
        ]
      }

      # Non-matching event should skip the final function and continue
      info_event = make_event(%{"level" => "info"})
      assert {:ok, result} = Pipeline.execute(pipeline, info_event)
      assert Event.get_field(result, "step1") == nil
      assert Event.get_field(result, "step2") == "done"

      # Matching event should execute the final function and stop
      error_event = make_event(%{"level" => "error"})
      assert {:ok, result} = Pipeline.execute(pipeline, error_event)
      assert Event.get_field(result, "step1") == "done"
      assert Event.get_field(result, "step2") == nil
    end
  end

  describe "execute/2 with disabled functions" do
    test "skips disabled functions" do
      pipeline = %Pipeline{
        functions: [
          %PipelineFunction{
            module: Eval,
            config: %{fields: [{"step1", fn _e -> "done" end}]},
            enabled: false
          },
          %PipelineFunction{
            module: Eval,
            config: %{fields: [{"step2", fn _e -> "done" end}]}
          }
        ]
      }

      event = make_event()
      assert {:ok, result} = Pipeline.execute(pipeline, event)
      assert Event.get_field(result, "step1") == nil
      assert Event.get_field(result, "step2") == "done"
    end

    test "skips all disabled functions" do
      pipeline = %Pipeline{
        functions: [
          %PipelineFunction{module: Drop, config: %{}, enabled: false},
          %PipelineFunction{module: Drop, config: %{}, enabled: false}
        ]
      }

      event = make_event()
      assert {:ok, ^event} = Pipeline.execute(pipeline, event)
    end
  end

  describe "execute/2 with drop" do
    test "drop stops processing and returns drop signal" do
      pipeline = %Pipeline{
        functions: [
          %PipelineFunction{module: Drop, config: %{}},
          %PipelineFunction{
            module: Eval,
            config: %{fields: [{"should_not_run", fn _e -> true end}]}
          }
        ]
      }

      event = make_event()
      assert {:drop, "matched drop filter"} = Pipeline.execute(pipeline, event)
    end
  end

  describe "execute/2 with comment" do
    test "comment does not modify event" do
      pipeline = %Pipeline{
        functions: [
          %PipelineFunction{
            module: Comment,
            config: %{text: "This is a documentation comment"}
          }
        ]
      }

      event = make_event()
      assert {:ok, ^event} = Pipeline.execute(pipeline, event)
    end
  end

  describe "execute/2 complex pipeline" do
    test "multi-function pipeline with filters, final, and disabled" do
      pipeline = %Pipeline{
        functions: [
          # Comment - no-op
          %PipelineFunction{
            module: Comment,
            config: %{text: "Start processing"}
          },
          # Disabled eval - should be skipped
          %PipelineFunction{
            module: Eval,
            config: %{fields: [{"disabled_field", fn _e -> "nope" end}]},
            enabled: false
          },
          # Eval that only runs on error events
          %PipelineFunction{
            module: Eval,
            config: %{fields: [{"is_error", fn _e -> true end}]},
            filter: fn e -> Event.get_field(e, "level") == "error" end
          },
          # Mask that runs on all events
          %PipelineFunction{
            module: Mask,
            config: %{
              rules: [%{regex: ~r/secret/, replacement: "REDACTED"}],
              fields: ["_raw"]
            }
          }
        ]
      }

      event = make_event(%{"_raw" => "contains a secret value", "level" => "info"})
      assert {:ok, result} = Pipeline.execute(pipeline, event)
      assert Event.get_field(result, "disabled_field") == nil
      assert Event.get_field(result, "is_error") == nil
      assert Event.get_field(result, "_raw") == "contains a REDACTED value"
    end
  end
end
