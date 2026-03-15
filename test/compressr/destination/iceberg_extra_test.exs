defmodule Compressr.Destination.IcebergExtraTest do
  use ExUnit.Case, async: false

  alias Compressr.Destination.Iceberg
  alias Compressr.Event

  @test_bucket "compressr-test-events"

  describe "init/1 with atom config values" do
    test "parses atom :daily partition_by" do
      config = %{"bucket" => @test_bucket, "prefix" => "ice-atom-daily", "partition_by" => :daily}
      {:ok, state} = Iceberg.init(config)
      assert state.partition_by == :daily
    end

    test "parses atom :hourly partition_by" do
      config = %{"bucket" => @test_bucket, "prefix" => "ice-atom-hourly", "partition_by" => :hourly}
      {:ok, state} = Iceberg.init(config)
      assert state.partition_by == :hourly
    end

    test "parses unknown partition_by defaults to daily" do
      config = %{"bucket" => @test_bucket, "prefix" => "ice-unknown-pb", "partition_by" => "weekly"}
      {:ok, state} = Iceberg.init(config)
      assert state.partition_by == :daily
    end

    test "parses atom :gzip compression" do
      config = %{"bucket" => @test_bucket, "prefix" => "ice-atom-gzip", "compression" => :gzip}
      {:ok, state} = Iceberg.init(config)
      assert state.compression == :gzip
    end

    test "parses atom :none compression" do
      config = %{"bucket" => @test_bucket, "prefix" => "ice-atom-none", "compression" => :none}
      {:ok, state} = Iceberg.init(config)
      assert state.compression == :none
    end

    test "parses atom :snappy compression falls back to gzip" do
      config = %{"bucket" => @test_bucket, "prefix" => "ice-atom-snappy", "compression" => :snappy}
      {:ok, state} = Iceberg.init(config)
      assert state.compression == :gzip
    end

    test "parses atom :zstd compression falls back to gzip" do
      config = %{"bucket" => @test_bucket, "prefix" => "ice-atom-zstd", "compression" => :zstd}
      {:ok, state} = Iceberg.init(config)
      assert state.compression == :gzip
    end

    test "parses unknown compression defaults to gzip" do
      config = %{"bucket" => @test_bucket, "prefix" => "ice-unknown-comp", "compression" => "lz4"}
      {:ok, state} = Iceberg.init(config)
      assert state.compression == :gzip
    end
  end

  describe "send_batch/2 with STANDARD storage class" do
    test "writes with STANDARD storage class" do
      prefix = "ice-std-sc"

      config = %{
        "bucket" => @test_bucket,
        "prefix" => prefix,
        "storage_class" => "STANDARD",
        "compression" => "none",
        "min_file_size_bytes" => 1
      }

      {:ok, state} = Iceberg.init(config)

      events = [Event.new(%{"_raw" => "standard storage class test event", "_time" => 1_773_570_600})]
      {:ok, new_state} = Iceberg.send_batch(events, state)
      assert new_state.total_files >= 1
    end
  end

  describe "send_batch/2 with custom storage class" do
    test "writes with custom storage class" do
      prefix = "ice-custom-sc"

      config = %{
        "bucket" => @test_bucket,
        "prefix" => prefix,
        "storage_class" => "ONEZONE_IA",
        "compression" => "none",
        "min_file_size_bytes" => 1
      }

      {:ok, state} = Iceberg.init(config)

      events = [Event.new(%{"_raw" => "custom storage class test event data", "_time" => 1_773_570_600})]
      {:ok, new_state} = Iceberg.send_batch(events, state)
      assert new_state.total_files >= 1
    end
  end

  describe "stop/1 with empty buffers" do
    test "stop with no buffered data is ok" do
      config = %{"bucket" => @test_bucket, "prefix" => "ice-stop-empty"}
      {:ok, state} = Iceberg.init(config)
      assert :ok = Iceberg.stop(state)
    end
  end
end
