defmodule Compressr.Routing.ConfigTest do
  use ExUnit.Case, async: false

  alias Compressr.Routing.Config

  setup do
    clean_items("route")
    :ok
  end

  describe "save/1" do
    test "saves a valid route config" do
      config = valid_route()
      assert {:ok, saved} = Config.save(config)
      assert saved["id"] == "test-route-1"
      assert saved["name"] == "Test Route"
      assert saved["pipeline_id"] == "pipe-1"
      assert saved["destination_id"] == "dest-1"
      assert saved["enabled"] == true
      assert saved["final"] == true
      assert saved["inserted_at"] != nil
      assert saved["updated_at"] != nil
    end

    test "saves config with atom keys" do
      config = %{
        id: "atom-route",
        name: "Atom Route",
        pipeline_id: "pipe-1",
        destination_id: "dest-1"
      }

      assert {:ok, saved} = Config.save(config)
      assert saved["id"] == "atom-route"
    end

    test "returns error when missing required fields" do
      assert {:error, {:missing_fields, missing}} = Config.save(%{"id" => "r1"})
      assert "name" in missing
      assert "pipeline_id" in missing
      assert "destination_id" in missing
    end

    test "returns error when id is empty" do
      config = %{"id" => "", "name" => "test", "pipeline_id" => "p", "destination_id" => "d"}
      assert {:error, {:missing_fields, missing}} = Config.save(config)
      assert "id" in missing
    end

    test "returns error when all required fields are missing" do
      assert {:error, {:missing_fields, missing}} = Config.save(%{})
      assert length(missing) == 4
    end

    test "saves config with custom position" do
      config = Map.put(valid_route(), "position", 42)
      {:ok, saved} = Config.save(config)
      assert saved["position"] == 42
    end

    test "defaults position to 0" do
      {:ok, saved} = Config.save(valid_route())
      # Position defaults come from the merge
      assert is_integer(saved["position"])
    end

    test "saves config with filter string" do
      config = Map.put(valid_route(), "filter", "source == 'apache'")
      {:ok, saved} = Config.save(config)
      assert saved["filter"] == "source == 'apache'"
    end

    test "saves config with enabled=false" do
      config = Map.put(valid_route(), "enabled", false)
      {:ok, saved} = Config.save(config)
      assert saved["enabled"] == false
    end

    test "saves config with final=false" do
      config = Map.put(valid_route(), "final", false)
      {:ok, saved} = Config.save(config)
      assert saved["final"] == false
    end

    test "saves config with description" do
      config = Map.put(valid_route(), "description", "Routes apache logs to S3")
      {:ok, saved} = Config.save(config)
      assert saved["description"] == "Routes apache logs to S3"
    end
  end

  describe "get/1" do
    test "returns the config when it exists" do
      {:ok, _} = Config.save(valid_route())
      assert {:ok, config} = Config.get("test-route-1")
      assert config["id"] == "test-route-1"
      assert config["name"] == "Test Route"
      assert config["pipeline_id"] == "pipe-1"
      assert config["destination_id"] == "dest-1"
    end

    test "returns nil when config does not exist" do
      assert {:ok, nil} = Config.get("nonexistent")
    end

    test "correctly deserializes boolean fields" do
      config = Map.merge(valid_route(), %{"enabled" => false, "final" => false})
      {:ok, _} = Config.save(config)
      {:ok, fetched} = Config.get("test-route-1")
      assert fetched["enabled"] == false
      assert fetched["final"] == false
    end

    test "correctly deserializes position as integer" do
      config = Map.put(valid_route(), "position", 99)
      {:ok, _} = Config.save(config)
      {:ok, fetched} = Config.get("test-route-1")
      assert fetched["position"] == 99
      assert is_integer(fetched["position"])
    end
  end

  describe "list/0" do
    test "returns empty list when no configs exist" do
      assert {:ok, []} = Config.list()
    end

    test "returns all configs sorted by position" do
      for {i, pos} <- [{1, 30}, {2, 10}, {3, 20}] do
        config = %{
          "id" => "list-route-#{i}",
          "name" => "List #{i}",
          "pipeline_id" => "pipe-1",
          "destination_id" => "dest-1",
          "position" => pos
        }

        {:ok, _} = Config.save(config)
      end

      {:ok, configs} = Config.list()
      assert length(configs) == 3
      positions = Enum.map(configs, & &1["position"])
      assert positions == Enum.sort(positions)
    end
  end

  describe "delete/1" do
    test "deletes an existing config" do
      {:ok, _} = Config.save(valid_route())
      assert :ok = Config.delete("test-route-1")
      assert {:ok, nil} = Config.get("test-route-1")
    end

    test "deleting nonexistent config is idempotent" do
      assert :ok = Config.delete("does-not-exist")
    end
  end

  defp valid_route do
    %{
      "id" => "test-route-1",
      "name" => "Test Route",
      "pipeline_id" => "pipe-1",
      "destination_id" => "dest-1",
      "filter" => "true"
    }
  end

  defp clean_items(prefix) do
    result =
      ExAws.Dynamo.scan("compressr_test_config",
        filter_expression: "pk = :pk",
        expression_attribute_values: [pk: prefix]
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
