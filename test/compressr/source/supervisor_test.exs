defmodule Compressr.Source.SupervisorTest do
  use ExUnit.Case, async: false

  alias Compressr.Source.Supervisor, as: SourceSupervisor
  alias Compressr.Source.Config

  setup do
    # Clean up source configs
    clean_sources()
    # Stop any existing source processes
    children = DynamicSupervisor.which_children(SourceSupervisor)

    Enum.each(children, fn {id, pid, _type, _mods} ->
      if is_pid(pid) do
        DynamicSupervisor.terminate_child(SourceSupervisor, pid)
      end
    end)

    :ok
  end

  describe "start_source/1" do
    test "starts a syslog source process" do
      config = %{
        "id" => "sup-src-1",
        "type" => "syslog",
        "config" => %{"udp_port" => 9990, "protocol" => "udp"},
        "enabled" => true
      }

      assert {:ok, pid} = SourceSupervisor.start_source(config)
      assert Process.alive?(pid)

      SourceSupervisor.stop_source("sup-src-1")
    end

    test "starts a HEC source process" do
      config = %{
        "id" => "sup-src-hec",
        "type" => "hec",
        "config" => %{"port" => 8088},
        "enabled" => true
      }

      assert {:ok, pid} = SourceSupervisor.start_source(config)
      assert Process.alive?(pid)

      SourceSupervisor.stop_source("sup-src-hec")
    end

    test "returns error for unknown source type" do
      config = %{
        "id" => "sup-src-bad",
        "type" => "unknown_type",
        "config" => %{},
        "enabled" => true
      }

      assert {:error, :unknown_type} = SourceSupervisor.start_source(config)
    end
  end

  describe "stop_source/1" do
    test "returns error when source not found" do
      assert {:error, :not_found} = SourceSupervisor.stop_source("nonexistent-source")
    end
  end

  describe "restart_source/1" do
    test "restart works for a new source" do
      config = %{
        "id" => "sup-restart-new",
        "type" => "syslog",
        "config" => %{"udp_port" => 9986, "protocol" => "udp"},
        "enabled" => true
      }

      {:ok, pid} = SourceSupervisor.restart_source(config)
      assert Process.alive?(pid)

      # Clean up via terminate_child directly
      DynamicSupervisor.terminate_child(SourceSupervisor, pid)
    end
  end

  describe "load_sources/0" do
    test "loads and starts enabled sources from DynamoDB" do
      # Save an enabled source config
      config = %{
        "id" => "sup-load-1",
        "name" => "Load Test",
        "type" => "syslog",
        "config" => %{"udp_port" => 9985, "protocol" => "udp"},
        "enabled" => true
      }

      {:ok, _} = Config.save(config)

      SourceSupervisor.load_sources()

      # Give it time to start
      :timer.sleep(50)

      # Verify the source is running via the Registry
      children = DynamicSupervisor.which_children(SourceSupervisor)
      assert Enum.any?(children, fn {_, pid, _, _} -> is_pid(pid) end)

      # Clean up
      Enum.each(children, fn {_, pid, _, _} ->
        if is_pid(pid), do: DynamicSupervisor.terminate_child(SourceSupervisor, pid)
      end)
    end

    test "does not start disabled sources" do
      # Get children count before
      children_before = DynamicSupervisor.which_children(SourceSupervisor)
      count_before = length(Enum.filter(children_before, fn {_, pid, _, _} -> is_pid(pid) end))

      config = %{
        "id" => "sup-load-disabled",
        "name" => "Disabled Source",
        "type" => "syslog",
        "config" => %{"udp_port" => 9984, "protocol" => "udp"},
        "enabled" => false
      }

      {:ok, _} = Config.save(config)

      SourceSupervisor.load_sources()
      :timer.sleep(50)

      children_after = DynamicSupervisor.which_children(SourceSupervisor)
      count_after = length(Enum.filter(children_after, fn {_, pid, _, _} -> is_pid(pid) end))

      # Should not have started any new children
      assert count_after == count_before
    end
  end

  defp clean_sources do
    result =
      ExAws.Dynamo.scan("compressr_test_config",
        filter_expression: "pk = :pk",
        expression_attribute_values: [pk: "source"]
      )
      |> ExAws.request!()

    items = Map.get(result, "Items", [])

    Enum.each(items, fn item ->
      pk = get_in(item, ["pk", "S"])
      sk = get_in(item, ["sk", "S"])

      if pk && sk do
        ExAws.Dynamo.delete_item("compressr_test_config", %{"pk" => pk, "sk" => sk})
        |> ExAws.request!()
      end
    end)
  end
end
