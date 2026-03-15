defmodule Compressr.Destination.ConfigExtraTest do
  use ExUnit.Case, async: false

  alias Compressr.Destination.Config

  setup do
    case Config.list() do
      {:ok, configs} -> Enum.each(configs, fn c -> Config.delete(c.id) end)
      _ -> :ok
    end

    :ok
  end

  describe "backpressure_mode parsing" do
    test "persists and retrieves :block mode" do
      config = %Config{
        id: "bp-block",
        name: "Block Mode",
        type: "devnull",
        config: %{},
        enabled: true,
        backpressure_mode: :block
      }

      {:ok, _} = Config.save(config)
      {:ok, fetched} = Config.get("bp-block")
      assert fetched.backpressure_mode == :block
    end

    test "persists and retrieves :drop mode" do
      config = %Config{
        id: "bp-drop",
        name: "Drop Mode",
        type: "devnull",
        config: %{},
        enabled: true,
        backpressure_mode: :drop
      }

      {:ok, _} = Config.save(config)
      {:ok, fetched} = Config.get("bp-drop")
      assert fetched.backpressure_mode == :drop
    end

    test "persists and retrieves :queue mode" do
      config = %Config{
        id: "bp-queue",
        name: "Queue Mode",
        type: "devnull",
        config: %{},
        enabled: true,
        backpressure_mode: :queue
      }

      {:ok, _} = Config.save(config)
      {:ok, fetched} = Config.get("bp-queue")
      assert fetched.backpressure_mode == :queue
    end

    test "defaults to :block when nil" do
      config = %Config{
        id: "bp-nil",
        name: "Nil BP",
        type: "devnull",
        config: %{},
        enabled: true,
        backpressure_mode: nil
      }

      {:ok, _} = Config.save(config)
      {:ok, fetched} = Config.get("bp-nil")
      assert fetched.backpressure_mode == :block
    end
  end

  describe "config field serialization" do
    test "serializes and deserializes nested config map" do
      config = %Config{
        id: "nested-cfg",
        name: "Nested Config",
        type: "s3",
        config: %{
          "bucket" => "my-bucket",
          "prefix" => "logs/",
          "region" => "us-east-1",
          "storage_class" => "STANDARD_IA"
        },
        enabled: true,
        backpressure_mode: :block
      }

      {:ok, _} = Config.save(config)
      {:ok, fetched} = Config.get("nested-cfg")
      assert fetched.config["bucket"] == "my-bucket"
      assert fetched.config["prefix"] == "logs/"
      assert fetched.config["region"] == "us-east-1"
      assert fetched.config["storage_class"] == "STANDARD_IA"
    end

    test "handles nil config" do
      config = %Config{
        id: "nil-cfg",
        name: "Nil Config",
        type: "devnull",
        config: nil,
        enabled: true,
        backpressure_mode: :block
      }

      {:ok, _} = Config.save(config)
      {:ok, fetched} = Config.get("nil-cfg")
      assert fetched.config == %{}
    end

    test "handles empty config" do
      config = %Config{
        id: "empty-cfg",
        name: "Empty Config",
        type: "devnull",
        config: %{},
        enabled: true,
        backpressure_mode: :block
      }

      {:ok, _} = Config.save(config)
      {:ok, fetched} = Config.get("empty-cfg")
      assert fetched.config == %{}
    end
  end

  describe "post_processing_pipeline_id" do
    test "nil is stored and retrieved as nil" do
      config = %Config{
        id: "pp-nil",
        name: "No Post Pipeline",
        type: "devnull",
        config: %{},
        enabled: true,
        backpressure_mode: :block,
        post_processing_pipeline_id: nil
      }

      {:ok, _} = Config.save(config)
      {:ok, fetched} = Config.get("pp-nil")
      assert fetched.post_processing_pipeline_id == nil
    end

    test "non-empty string is stored and retrieved" do
      config = %Config{
        id: "pp-set",
        name: "With Post Pipeline",
        type: "devnull",
        config: %{},
        enabled: true,
        backpressure_mode: :block,
        post_processing_pipeline_id: "post-pipe-123"
      }

      {:ok, _} = Config.save(config)
      {:ok, fetched} = Config.get("pp-set")
      assert fetched.post_processing_pipeline_id == "post-pipe-123"
    end
  end

  describe "enabled field" do
    test "saves enabled=false" do
      config = %Config{
        id: "disabled-dest",
        name: "Disabled Dest",
        type: "devnull",
        config: %{},
        enabled: false,
        backpressure_mode: :block
      }

      {:ok, _} = Config.save(config)
      {:ok, fetched} = Config.get("disabled-dest")
      assert fetched.enabled == false
    end

    test "saves enabled=true" do
      config = %Config{
        id: "enabled-dest",
        name: "Enabled Dest",
        type: "devnull",
        config: %{},
        enabled: true,
        backpressure_mode: :block
      }

      {:ok, _} = Config.save(config)
      {:ok, fetched} = Config.get("enabled-dest")
      assert fetched.enabled == true
    end
  end

  describe "auto-generated ID" do
    test "generates unique IDs" do
      config1 = %Config{name: "Auto 1", type: "devnull", config: %{}, enabled: true, backpressure_mode: :block}
      config2 = %Config{name: "Auto 2", type: "devnull", config: %{}, enabled: true, backpressure_mode: :block}

      {:ok, saved1} = Config.save(config1)
      {:ok, saved2} = Config.save(config2)

      assert saved1.id != saved2.id
      assert is_binary(saved1.id)
      assert is_binary(saved2.id)
    end
  end
end
