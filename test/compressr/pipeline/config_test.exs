defmodule Compressr.Pipeline.ConfigTest do
  use ExUnit.Case, async: false

  alias Compressr.Pipeline.Config

  setup do
    clean_items("pipeline")
    :ok
  end

  describe "save/1" do
    test "saves a valid pipeline config" do
      config = valid_pipeline()
      assert {:ok, saved} = Config.save(config)
      assert saved["id"] == "test-pipe-1"
      assert saved["name"] == "Test Pipeline"
      assert saved["enabled"] == true
      assert saved["inserted_at"] != nil
      assert saved["updated_at"] != nil
    end

    test "saves config with atom keys" do
      config = %{id: "atom-pipe", name: "Atom Pipeline", functions: []}
      assert {:ok, saved} = Config.save(config)
      assert saved["id"] == "atom-pipe"
      assert saved["name"] == "Atom Pipeline"
    end

    test "saves config with functions list" do
      config = %{
        "id" => "func-pipe",
        "name" => "Pipeline With Functions",
        "functions" => [
          %{"type" => "eval", "config" => %{"field" => "test"}},
          %{"type" => "drop", "config" => %{}}
        ]
      }

      assert {:ok, saved} = Config.save(config)
      assert length(saved["functions"]) == 2
    end

    test "returns error when missing required fields" do
      assert {:error, {:missing_fields, missing}} = Config.save(%{"name" => "No ID"})
      assert "id" in missing
    end

    test "returns error when id is empty string" do
      assert {:error, {:missing_fields, missing}} = Config.save(%{"id" => "", "name" => "test"})
      assert "id" in missing
    end

    test "returns error when name is empty string" do
      assert {:error, {:missing_fields, missing}} = Config.save(%{"id" => "x", "name" => ""})
      assert "name" in missing
    end

    test "returns error when both id and name are missing" do
      assert {:error, {:missing_fields, missing}} = Config.save(%{})
      assert "id" in missing
      assert "name" in missing
    end

    test "updates an existing config" do
      config = valid_pipeline()
      {:ok, _first} = Config.save(config)

      # Small delay to ensure different timestamps
      :timer.sleep(10)
      updated = Map.put(config, "name", "Updated")
      {:ok, _second} = Config.save(updated)

      {:ok, fetched} = Config.get("test-pipe-1")
      assert fetched["name"] == "Updated"
    end

    test "saves config with description" do
      config = Map.put(valid_pipeline(), "description", "A test pipeline for unit tests")
      {:ok, saved} = Config.save(config)
      assert saved["description"] == "A test pipeline for unit tests"
    end

    test "saves config with enabled=false" do
      config = Map.put(valid_pipeline(), "enabled", false)
      {:ok, saved} = Config.save(config)
      assert saved["enabled"] == false
    end

    test "defaults enabled to true when not provided" do
      config = %{"id" => "default-enabled", "name" => "Default Enabled"}
      {:ok, saved} = Config.save(config)
      assert saved["enabled"] == true
    end

    test "defaults functions to empty list when not provided" do
      config = %{"id" => "no-funcs", "name" => "No Functions"}
      {:ok, saved} = Config.save(config)

      {:ok, fetched} = Config.get("no-funcs")
      assert fetched["functions"] == []
    end
  end

  describe "get/1" do
    test "returns the config when it exists" do
      {:ok, _} = Config.save(valid_pipeline())
      assert {:ok, config} = Config.get("test-pipe-1")
      assert config["id"] == "test-pipe-1"
      assert config["name"] == "Test Pipeline"
    end

    test "returns nil when config does not exist" do
      assert {:ok, nil} = Config.get("nonexistent")
    end

    test "correctly deserializes functions from JSON" do
      config = %{
        "id" => "json-funcs",
        "name" => "JSON Functions",
        "functions" => [%{"type" => "eval"}]
      }

      {:ok, _} = Config.save(config)
      {:ok, fetched} = Config.get("json-funcs")
      assert is_list(fetched["functions"])
      assert length(fetched["functions"]) == 1
    end

    test "correctly deserializes enabled boolean" do
      config = %{"id" => "bool-test", "name" => "Bool Test", "enabled" => false}
      {:ok, _} = Config.save(config)
      {:ok, fetched} = Config.get("bool-test")
      assert fetched["enabled"] == false
    end
  end

  describe "list/0" do
    test "returns empty list when no configs exist" do
      assert {:ok, []} = Config.list()
    end

    test "returns all configs" do
      for i <- 1..3 do
        {:ok, _} = Config.save(%{"id" => "list-pipe-#{i}", "name" => "List #{i}"})
      end

      {:ok, configs} = Config.list()
      assert length(configs) == 3
    end
  end

  describe "delete/1" do
    test "deletes an existing config" do
      {:ok, _} = Config.save(valid_pipeline())
      assert :ok = Config.delete("test-pipe-1")
      assert {:ok, nil} = Config.get("test-pipe-1")
    end

    test "deleting nonexistent config is idempotent" do
      assert :ok = Config.delete("does-not-exist")
    end
  end

  defp valid_pipeline do
    %{
      "id" => "test-pipe-1",
      "name" => "Test Pipeline",
      "functions" => [],
      "description" => "A test pipeline"
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
