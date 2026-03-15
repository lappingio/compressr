defmodule Compressr.Pipeline.Functions.RenameTest do
  use ExUnit.Case, async: true

  alias Compressr.Event
  alias Compressr.Pipeline.Functions.Rename

  defp make_event(fields \\ %{}) do
    Event.new(Map.merge(%{"_raw" => "test data", "host" => "web1"}, fields))
  end

  describe "execute/2 explicit renames" do
    test "renames a single field" do
      event = make_event(%{"src_ip" => "192.168.1.1"})
      config = %{renames: %{"src_ip" => "source_address"}}

      assert {:ok, result} = Rename.execute(event, config)
      assert Event.get_field(result, "source_address") == "192.168.1.1"
      assert Event.get_field(result, "src_ip") == nil
    end

    test "renames multiple fields" do
      event = make_event(%{"src_ip" => "192.168.1.1", "dst_ip" => "10.0.0.1"})

      config = %{
        renames: %{"src_ip" => "source_address", "dst_ip" => "dest_address"}
      }

      assert {:ok, result} = Rename.execute(event, config)
      assert Event.get_field(result, "source_address") == "192.168.1.1"
      assert Event.get_field(result, "dest_address") == "10.0.0.1"
      assert Event.get_field(result, "src_ip") == nil
      assert Event.get_field(result, "dst_ip") == nil
    end

    test "preserves field value during rename" do
      event = make_event(%{"data" => %{"nested" => [1, 2, 3]}})
      config = %{renames: %{"data" => "payload"}}

      assert {:ok, result} = Rename.execute(event, config)
      assert Event.get_field(result, "payload") == %{"nested" => [1, 2, 3]}
      assert Event.get_field(result, "data") == nil
    end

    test "no-op when source field does not exist" do
      event = make_event()
      config = %{renames: %{"nonexistent" => "new_name"}}

      assert {:ok, result} = Rename.execute(event, config)
      assert Event.get_field(result, "new_name") == nil
    end

    test "overwrites existing field at target name" do
      event = make_event(%{"old_name" => "value1", "new_name" => "value2"})
      config = %{renames: %{"old_name" => "new_name"}}

      assert {:ok, result} = Rename.execute(event, config)
      assert Event.get_field(result, "new_name") == "value1"
      assert Event.get_field(result, "old_name") == nil
    end
  end

  describe "execute/2 with rename_fn" do
    test "applies dynamic rename function" do
      event = make_event(%{"UPPER_FIELD" => "value"})

      config = %{
        rename_fn: fn e ->
          Enum.reduce(e, %{}, fn {k, v}, acc ->
            if is_binary(k) do
              Map.put(acc, String.downcase(k), v)
            else
              Map.put(acc, k, v)
            end
          end)
        end
      }

      assert {:ok, result} = Rename.execute(event, config)
      assert Event.get_field(result, "upper_field") == "value"
    end

    test "explicit renames execute before rename_fn" do
      event = make_event(%{"a" => "1"})

      config = %{
        renames: %{"a" => "b"},
        rename_fn: fn e ->
          # At this point, "a" should already be renamed to "b"
          if Map.has_key?(e, "b") do
            Event.put_field(e, "saw_b", true)
          else
            e
          end
        end
      }

      assert {:ok, result} = Rename.execute(event, config)
      assert Event.get_field(result, "b") == "1"
      assert Event.get_field(result, "saw_b") == true
      assert Event.get_field(result, "a") == nil
    end
  end

  describe "execute/2 edge cases" do
    test "empty config is a no-op" do
      event = make_event()
      assert {:ok, ^event} = Rename.execute(event, %{})
    end

    test "empty renames map is a no-op" do
      event = make_event()
      assert {:ok, ^event} = Rename.execute(event, %{renames: %{}})
    end

    test "returns error on exception in rename_fn" do
      event = make_event()

      config = %{
        rename_fn: fn _e -> raise "boom" end
      }

      assert {:error, "boom"} = Rename.execute(event, config)
    end

    test "does not rename internal fields via delete_field guard" do
      event = make_event() |> Event.put_internal("__meta", "val")
      config = %{renames: %{"__meta" => "meta"}}

      # get_field returns the value, but delete_field won't remove internal fields
      assert {:ok, result} = Rename.execute(event, config)
      # The internal field should still exist since delete_field protects it
      assert Event.get_field(result, "__meta") == "val"
    end
  end
end
