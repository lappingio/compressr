defmodule Compressr.Source.ConfigTest do
  use ExUnit.Case, async: false

  alias Compressr.Source.Config

  setup do
    clean_sources()
    :ok
  end

  describe "save/1" do
    test "saves a valid source config" do
      config = valid_syslog_config()
      assert {:ok, saved} = Config.save(config)
      assert saved["id"] == "test-syslog-1"
      assert saved["name"] == "Test Syslog"
      assert saved["type"] == "syslog"
      assert saved["enabled"] == true
      assert saved["inserted_at"] != nil
      assert saved["updated_at"] != nil
    end

    test "saves config with atom keys" do
      config = %{
        id: "test-syslog-atom",
        name: "Atom Key Syslog",
        type: "syslog",
        config: %{"udp_port" => 5514, "protocol" => "udp"}
      }

      assert {:ok, saved} = Config.save(config)
      assert saved["id"] == "test-syslog-atom"
    end

    test "saves config with enabled=false" do
      config = Map.put(valid_syslog_config(), "enabled", false)
      assert {:ok, saved} = Config.save(config)
      assert saved["enabled"] == false
    end

    test "saves config with pre_processing_pipeline_id" do
      config = Map.put(valid_syslog_config(), "pre_processing_pipeline_id", "pipeline-123")
      assert {:ok, saved} = Config.save(config)
      assert saved["pre_processing_pipeline_id"] == "pipeline-123"
    end

    test "returns error when missing required fields" do
      assert {:error, {:missing_fields, missing}} = Config.save(%{"id" => "test-1"})
      assert "name" in missing
      assert "type" in missing
      assert "config" in missing
    end

    test "returns error for unknown source type" do
      config = %{
        "id" => "test-bad-type",
        "name" => "Bad Type",
        "type" => "nonexistent",
        "config" => %{}
      }

      assert {:error, :unknown_type} = Config.save(config)
    end

    test "returns error for invalid type-specific config" do
      config = %{
        "id" => "test-bad-config",
        "name" => "Bad Config",
        "type" => "syslog",
        "config" => %{"protocol" => "udp"}
        # missing udp_port
      }

      assert {:error, {:missing_fields, ["udp_port"]}} = Config.save(config)
    end
  end

  describe "get/1" do
    test "retrieves a saved config by ID" do
      config = valid_syslog_config()
      {:ok, _} = Config.save(config)

      assert {:ok, retrieved} = Config.get("test-syslog-1")
      assert retrieved["id"] == "test-syslog-1"
      assert retrieved["name"] == "Test Syslog"
      assert retrieved["type"] == "syslog"
      assert is_map(retrieved["config"])
      assert retrieved["config"]["udp_port"] == 5514
    end

    test "returns nil for non-existent ID" do
      assert {:ok, nil} = Config.get("does-not-exist")
    end
  end

  describe "list/0" do
    test "returns empty list when no sources configured" do
      assert {:ok, []} = Config.list()
    end

    test "returns all saved source configs" do
      {:ok, _} = Config.save(valid_syslog_config())
      {:ok, _} = Config.save(valid_hec_config())

      {:ok, configs} = Config.list()
      assert length(configs) == 2

      ids = Enum.map(configs, & &1["id"])
      assert "test-syslog-1" in ids
      assert "test-hec-1" in ids
    end
  end

  describe "delete/1" do
    test "deletes a source config" do
      {:ok, _} = Config.save(valid_syslog_config())
      assert {:ok, _} = Config.get("test-syslog-1")

      assert :ok = Config.delete("test-syslog-1")
      assert {:ok, nil} = Config.get("test-syslog-1")
    end

    test "deleting non-existent config does not error" do
      assert :ok = Config.delete("nonexistent")
    end
  end

  # --- Helpers ---

  defp valid_syslog_config do
    %{
      "id" => "test-syslog-1",
      "name" => "Test Syslog",
      "type" => "syslog",
      "config" => %{"udp_port" => 5514, "protocol" => "udp"}
    }
  end

  defp valid_hec_config do
    %{
      "id" => "test-hec-1",
      "name" => "Test HEC",
      "type" => "hec",
      "config" => %{"port" => 8088}
    }
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

      ExAws.Dynamo.delete_item("compressr_test_config", %{"pk" => pk, "sk" => sk})
      |> ExAws.request!()
    end)
  end
end
