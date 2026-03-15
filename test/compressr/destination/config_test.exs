defmodule Compressr.Destination.ConfigTest do
  use ExUnit.Case, async: false

  alias Compressr.Destination.Config

  setup do
    # Clean up any destination configs from previous test runs
    case Config.list() do
      {:ok, configs} ->
        Enum.each(configs, fn c -> Config.delete(c.id) end)

      _ ->
        :ok
    end

    :ok
  end

  describe "save/1" do
    test "creates a new destination config" do
      config = %Config{
        id: "test-dest-1",
        name: "Test S3 Destination",
        type: "s3",
        config: %{"bucket" => "my-bucket", "prefix" => "logs"},
        enabled: true,
        backpressure_mode: :block
      }

      assert {:ok, saved} = Config.save(config)
      assert saved.id == "test-dest-1"
      assert saved.name == "Test S3 Destination"
      assert saved.type == "s3"
      assert saved.config == %{"bucket" => "my-bucket", "prefix" => "logs"}
      assert saved.enabled == true
      assert saved.backpressure_mode == :block
      assert saved.inserted_at != nil
      assert saved.updated_at != nil
    end

    test "generates an ID if not provided" do
      config = %Config{
        name: "Auto ID Dest",
        type: "devnull",
        config: %{},
        enabled: true,
        backpressure_mode: :drop
      }

      assert {:ok, saved} = Config.save(config)
      assert saved.id != nil
      assert is_binary(saved.id)
      assert String.length(saved.id) > 0
    end

    test "updates an existing config" do
      config = %Config{
        id: "test-dest-update",
        name: "Original Name",
        type: "s3",
        config: %{"bucket" => "bucket-1"},
        enabled: true,
        backpressure_mode: :block
      }

      {:ok, _} = Config.save(config)

      updated = %{config | name: "Updated Name", config: %{"bucket" => "bucket-2"}}
      {:ok, saved} = Config.save(updated)

      assert saved.name == "Updated Name"
      assert saved.config == %{"bucket" => "bucket-2"}

      {:ok, fetched} = Config.get("test-dest-update")
      assert fetched.name == "Updated Name"
    end

    test "saves with post_processing_pipeline_id" do
      config = %Config{
        id: "test-dest-pipeline",
        name: "With Pipeline",
        type: "s3",
        config: %{},
        enabled: true,
        backpressure_mode: :block,
        post_processing_pipeline_id: "pipeline-123"
      }

      {:ok, _} = Config.save(config)
      {:ok, fetched} = Config.get("test-dest-pipeline")
      assert fetched.post_processing_pipeline_id == "pipeline-123"
    end
  end

  describe "get/1" do
    test "returns the config when it exists" do
      config = %Config{
        id: "test-get-1",
        name: "Get Test",
        type: "devnull",
        config: %{"key" => "value"},
        enabled: false,
        backpressure_mode: :drop
      }

      {:ok, _} = Config.save(config)

      assert {:ok, fetched} = Config.get("test-get-1")
      assert fetched.id == "test-get-1"
      assert fetched.name == "Get Test"
      assert fetched.type == "devnull"
      assert fetched.config == %{"key" => "value"}
      assert fetched.enabled == false
      assert fetched.backpressure_mode == :drop
    end

    test "returns nil when config does not exist" do
      assert {:ok, nil} = Config.get("nonexistent-id")
    end
  end

  describe "list/0" do
    test "returns empty list when no configs exist" do
      assert {:ok, []} = Config.list()
    end

    test "returns all configs" do
      for i <- 1..3 do
        config = %Config{
          id: "test-list-#{i}",
          name: "List Test #{i}",
          type: "s3",
          config: %{},
          enabled: true,
          backpressure_mode: :block
        }

        {:ok, _} = Config.save(config)
      end

      {:ok, configs} = Config.list()
      assert length(configs) == 3

      ids = Enum.map(configs, & &1.id) |> Enum.sort()
      assert ids == ["test-list-1", "test-list-2", "test-list-3"]
    end
  end

  describe "delete/1" do
    test "deletes an existing config" do
      config = %Config{
        id: "test-delete-1",
        name: "Delete Test",
        type: "devnull",
        config: %{},
        enabled: true,
        backpressure_mode: :block
      }

      {:ok, _} = Config.save(config)
      assert :ok = Config.delete("test-delete-1")
      assert {:ok, nil} = Config.get("test-delete-1")
    end

    test "deleting a nonexistent config is idempotent" do
      assert :ok = Config.delete("does-not-exist")
    end
  end

  describe "backpressure_mode" do
    test "persists :queue mode" do
      config = %Config{
        id: "test-queue-mode",
        name: "Queue Mode",
        type: "s3",
        config: %{},
        enabled: true,
        backpressure_mode: :queue
      }

      {:ok, _} = Config.save(config)
      {:ok, fetched} = Config.get("test-queue-mode")
      assert fetched.backpressure_mode == :queue
    end
  end
end
