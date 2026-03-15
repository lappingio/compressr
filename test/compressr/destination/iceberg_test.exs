defmodule Compressr.Destination.IcebergTest do
  use ExUnit.Case, async: false

  alias Compressr.Destination.Iceberg
  alias Compressr.Event

  @test_bucket "compressr-test-events"

  setup do
    # Clean up test bucket objects with iceberg prefix
    case ExAws.S3.list_objects(@test_bucket, prefix: "iceberg-test") |> ExAws.request() do
      {:ok, %{body: %{contents: objects}}} when is_list(objects) ->
        Enum.each(objects, fn obj ->
          ExAws.S3.delete_object(@test_bucket, obj.key) |> ExAws.request()
        end)

      _ ->
        :ok
    end

    :ok
  end

  # ── init/1 ───────────────────────────────────────────────────────────

  describe "init/1" do
    test "initializes with valid config" do
      config = %{"bucket" => @test_bucket, "prefix" => "iceberg-test"}
      assert {:ok, %Iceberg{}} = Iceberg.init(config)
    end

    test "returns error when bucket is missing" do
      assert {:error, :bucket_required} = Iceberg.init(%{})
    end

    test "returns error when bucket is empty string" do
      assert {:error, :bucket_required} = Iceberg.init(%{"bucket" => ""})
    end

    test "applies default config values" do
      config = %{"bucket" => @test_bucket, "prefix" => "iceberg-test-defaults"}
      {:ok, state} = Iceberg.init(config)

      assert state.database_name == "default"
      assert state.table_name == "events"
      assert state.partition_by == :daily
      assert state.compression == :gzip
      assert state.storage_class == "INTELLIGENT_TIERING"
      assert state.min_file_size_bytes == 52_428_800
      assert state.file_close_interval_ms == 300_000
    end

    test "overrides defaults with provided config" do
      config = %{
        "bucket" => @test_bucket,
        "prefix" => "iceberg-test-custom",
        "database_name" => "mydb",
        "table_name" => "logs",
        "partition_by" => "hourly",
        "compression" => "none",
        "storage_class" => "STANDARD",
        "min_file_size_bytes" => 1_000,
        "file_close_interval_ms" => 60_000
      }

      {:ok, state} = Iceberg.init(config)

      assert state.database_name == "mydb"
      assert state.table_name == "logs"
      assert state.partition_by == :hourly
      assert state.compression == :none
      assert state.storage_class == "STANDARD"
      assert state.min_file_size_bytes == 1_000
      assert state.file_close_interval_ms == 60_000
    end

    test "snappy and zstd fall back to gzip in stub mode" do
      {:ok, snappy} = Iceberg.init(%{"bucket" => @test_bucket, "prefix" => "iceberg-test-snap", "compression" => "snappy"})
      {:ok, zstd} = Iceberg.init(%{"bucket" => @test_bucket, "prefix" => "iceberg-test-zstd", "compression" => "zstd"})

      assert snappy.compression == :gzip
      assert zstd.compression == :gzip
    end

    test "writes initial metadata.json to S3" do
      prefix = "iceberg-test-meta-init"
      config = %{"bucket" => @test_bucket, "prefix" => prefix, "database_name" => "testdb", "table_name" => "mytable"}
      {:ok, _state} = Iceberg.init(config)

      meta_key = "#{prefix}/testdb/mytable/metadata/metadata.json"
      {:ok, %{body: body}} = ExAws.S3.get_object(@test_bucket, meta_key) |> ExAws.request()
      {:ok, meta} = Jason.decode(body)

      assert meta["format-version"] == 2
      assert meta["location"] == "s3://#{@test_bucket}/#{prefix}/testdb/mytable"
      assert meta["properties"]["stub"] == "true"
    end
  end

  # ── send_batch/2 ─────────────────────────────────────────────────────

  describe "send_batch/2" do
    test "buffers events without flushing when under min_file_size" do
      config = %{
        "bucket" => @test_bucket,
        "prefix" => "iceberg-test-buffer",
        "min_file_size_bytes" => 10_000_000
      }

      {:ok, state} = Iceberg.init(config)

      events = [
        Event.new(%{"_raw" => "line1", "_time" => 1_773_570_600, "host" => "s1"}),
        Event.new(%{"_raw" => "line2", "_time" => 1_773_570_600, "host" => "s2"})
      ]

      {:ok, new_state} = Iceberg.send_batch(events, state)

      # Events should be buffered, not flushed
      total_buffered =
        new_state.partition_buffers
        |> Map.values()
        |> Enum.map(& &1.row_count)
        |> Enum.sum()

      assert total_buffered == 2
    end

    test "auto-flushes when buffer exceeds min_file_size_bytes" do
      prefix = "iceberg-test-autoflush"

      config = %{
        "bucket" => @test_bucket,
        "prefix" => prefix,
        "database_name" => "db",
        "table_name" => "tbl",
        "compression" => "none",
        "min_file_size_bytes" => 10
      }

      {:ok, state} = Iceberg.init(config)

      events = [
        Event.new(%{"_raw" => "a longer log line that exceeds the tiny limit", "_time" => 1_773_570_600}),
        Event.new(%{"_raw" => "another line also long enough", "_time" => 1_773_570_600})
      ]

      {:ok, new_state} = Iceberg.send_batch(events, state)

      # Buffer should be cleared after auto-flush
      assert new_state.partition_buffers == %{}
      assert new_state.total_files >= 1
    end

    test "partitions events by _time into different buffers" do
      config = %{
        "bucket" => @test_bucket,
        "prefix" => "iceberg-test-partition-buf",
        "min_file_size_bytes" => 10_000_000,
        "partition_by" => "daily"
      }

      {:ok, state} = Iceberg.init(config)

      events = [
        Event.new(%{"_raw" => "day1", "_time" => 1_773_570_600}),
        # next day
        Event.new(%{"_raw" => "day2", "_time" => 1_773_570_600 + 86_400})
      ]

      {:ok, new_state} = Iceberg.send_batch(events, state)
      assert map_size(new_state.partition_buffers) == 2
    end
  end

  # ── Partition paths ──────────────────────────────────────────────────

  describe "partition path structure in S3" do
    test "writes files in Iceberg-style partition layout" do
      prefix = "iceberg-test-paths"

      config = %{
        "bucket" => @test_bucket,
        "prefix" => prefix,
        "database_name" => "mydb",
        "table_name" => "events",
        "compression" => "none",
        "min_file_size_bytes" => 10
      }

      {:ok, state} = Iceberg.init(config)

      # 2026-03-15 10:30:00 UTC
      events = [
        Event.new(%{"_raw" => "test event with enough data to exceed threshold", "_time" => 1_773_570_600})
      ]

      {:ok, _state} = Iceberg.send_batch(events, state)

      {:ok, %{body: %{contents: objects}}} =
        ExAws.S3.list_objects(@test_bucket, prefix: "#{prefix}/mydb/events/data/")
        |> ExAws.request()

      data_objects = Enum.reject(objects, fn o -> String.contains?(o.key, "metadata") end)
      assert length(data_objects) >= 1

      [obj | _] = data_objects
      # Verify path contains partition layout: prefix/db/table/data/dt=YYYY-MM-DD/file.ndjson
      assert String.contains?(obj.key, "#{prefix}/mydb/events/data/dt=2026-03-15/")
      assert String.ends_with?(obj.key, ".ndjson")
    end

    test "hourly partitioning includes hour in path" do
      prefix = "iceberg-test-hourly"

      config = %{
        "bucket" => @test_bucket,
        "prefix" => prefix,
        "database_name" => "db",
        "table_name" => "logs",
        "compression" => "none",
        "partition_by" => "hourly",
        "min_file_size_bytes" => 10
      }

      {:ok, state} = Iceberg.init(config)

      # 2026-03-15 14:30:00 UTC
      events = [
        Event.new(%{"_raw" => "hourly partitioned event long enough", "_time" => 1_773_585_000})
      ]

      {:ok, _state} = Iceberg.send_batch(events, state)

      {:ok, %{body: %{contents: objects}}} =
        ExAws.S3.list_objects(@test_bucket, prefix: "#{prefix}/db/logs/data/")
        |> ExAws.request()

      data_objects = Enum.reject(objects, fn o -> String.contains?(o.key, "metadata") end)
      assert length(data_objects) >= 1

      [obj | _] = data_objects
      assert String.contains?(obj.key, "dt=2026-03-15-14/")
    end
  end

  # ── NDJSON content ───────────────────────────────────────────────────

  describe "NDJSON content" do
    test "writes valid NDJSON lines" do
      prefix = "iceberg-test-ndjson"

      config = %{
        "bucket" => @test_bucket,
        "prefix" => prefix,
        "database_name" => "db",
        "table_name" => "tbl",
        "compression" => "none",
        "min_file_size_bytes" => 10
      }

      {:ok, state} = Iceberg.init(config)

      events = [
        Event.new(%{"_raw" => "line1", "_time" => 1_773_570_600, "host" => "server1"}),
        Event.new(%{"_raw" => "line2", "_time" => 1_773_570_600, "host" => "server2"})
      ]

      {:ok, _state} = Iceberg.send_batch(events, state)

      {:ok, %{body: %{contents: objects}}} =
        ExAws.S3.list_objects(@test_bucket, prefix: "#{prefix}/db/tbl/data/")
        |> ExAws.request()

      data_objects = Enum.reject(objects, fn o -> String.contains?(o.key, "metadata") end)
      [obj | _] = data_objects

      {:ok, %{body: body}} = ExAws.S3.get_object(@test_bucket, obj.key) |> ExAws.request()

      lines = String.split(body, "\n", trim: true)
      assert length(lines) == 2

      Enum.each(lines, fn line ->
        assert {:ok, _} = Jason.decode(line)
      end)

      {:ok, first} = Jason.decode(hd(lines))
      assert first["host"] in ["server1", "server2"]
    end

    test "strips internal fields from output" do
      prefix = "iceberg-test-strip"

      config = %{
        "bucket" => @test_bucket,
        "prefix" => prefix,
        "database_name" => "db",
        "table_name" => "tbl",
        "compression" => "none",
        "min_file_size_bytes" => 10
      }

      {:ok, state} = Iceberg.init(config)

      event =
        Event.new(%{"_raw" => "test", "_time" => 1_773_570_600})
        |> Event.put_internal("__source_id", "src-1")

      {:ok, _state} = Iceberg.send_batch([event], state)

      {:ok, %{body: %{contents: objects}}} =
        ExAws.S3.list_objects(@test_bucket, prefix: "#{prefix}/db/tbl/data/")
        |> ExAws.request()

      data_objects = Enum.reject(objects, fn o -> String.contains?(o.key, "metadata") end)
      [obj | _] = data_objects

      {:ok, %{body: body}} = ExAws.S3.get_object(@test_bucket, obj.key) |> ExAws.request()
      {:ok, parsed} = body |> String.trim() |> Jason.decode()
      refute Map.has_key?(parsed, "__source_id")
    end
  end

  # ── Gzip compression ────────────────────────────────────────────────

  describe "gzip compression" do
    test "compresses output with gzip by default" do
      prefix = "iceberg-test-gzip"

      config = %{
        "bucket" => @test_bucket,
        "prefix" => prefix,
        "database_name" => "db",
        "table_name" => "tbl",
        "min_file_size_bytes" => 10
      }

      {:ok, state} = Iceberg.init(config)

      events = [
        Event.new(%{"_raw" => "compressed event data long enough to flush", "_time" => 1_773_570_600})
      ]

      {:ok, _state} = Iceberg.send_batch(events, state)

      {:ok, %{body: %{contents: objects}}} =
        ExAws.S3.list_objects(@test_bucket, prefix: "#{prefix}/db/tbl/data/")
        |> ExAws.request()

      data_objects = Enum.reject(objects, fn o -> String.contains?(o.key, "metadata") end)
      [obj | _] = data_objects

      assert String.ends_with?(obj.key, ".ndjson.gz")

      {:ok, %{body: body}} = ExAws.S3.get_object(@test_bucket, obj.key) |> ExAws.request()
      decompressed = :zlib.gunzip(body)
      lines = String.split(decompressed, "\n", trim: true)
      assert length(lines) >= 1

      {:ok, parsed} = Jason.decode(hd(lines))
      assert parsed["_raw"] == "compressed event data long enough to flush"
    end
  end

  # ── Min file size enforcement ────────────────────────────────────────

  describe "min file size enforcement" do
    test "does not flush until min_file_size_bytes is reached" do
      prefix = "iceberg-test-minsize"

      config = %{
        "bucket" => @test_bucket,
        "prefix" => prefix,
        "database_name" => "db",
        "table_name" => "tbl",
        "compression" => "none",
        "min_file_size_bytes" => 10_000_000
      }

      {:ok, state} = Iceberg.init(config)

      events = [Event.new(%{"_raw" => "small", "_time" => 1_773_570_600})]
      {:ok, new_state} = Iceberg.send_batch(events, state)

      # Should still be buffered
      total_buffered =
        new_state.partition_buffers
        |> Map.values()
        |> Enum.map(& &1.row_count)
        |> Enum.sum()

      assert total_buffered == 1
      assert new_state.total_files == 0

      # Nothing should be in S3 data path
      {:ok, %{body: %{contents: objects}}} =
        ExAws.S3.list_objects(@test_bucket, prefix: "#{prefix}/db/tbl/data/")
        |> ExAws.request()

      data_objects = Enum.reject(objects, fn o -> String.contains?(o.key, "metadata") end)
      assert data_objects == []
    end
  end

  # ── flush/1 ──────────────────────────────────────────────────────────

  describe "flush/1" do
    test "flushes all buffered partitions" do
      prefix = "iceberg-test-flush"

      config = %{
        "bucket" => @test_bucket,
        "prefix" => prefix,
        "database_name" => "db",
        "table_name" => "tbl",
        "compression" => "none",
        "min_file_size_bytes" => 10_000_000
      }

      {:ok, state} = Iceberg.init(config)

      events = [
        Event.new(%{"_raw" => "flush me", "_time" => 1_773_570_600}),
        Event.new(%{"_raw" => "flush me too", "_time" => 1_773_570_600})
      ]

      {:ok, buffered} = Iceberg.send_batch(events, state)
      assert map_size(buffered.partition_buffers) > 0

      {:ok, flushed} = Iceberg.flush(buffered)
      assert flushed.partition_buffers == %{}
      assert flushed.total_files >= 1
    end

    test "flush with empty buffers is a no-op" do
      config = %{"bucket" => @test_bucket, "prefix" => "iceberg-test-flush-noop"}
      {:ok, state} = Iceberg.init(config)
      assert {:ok, ^state} = Iceberg.flush(state)
    end
  end

  # ── Metadata stubs ──────────────────────────────────────────────────

  describe "metadata generation" do
    test "creates snapshot and manifest metadata on flush" do
      prefix = "iceberg-test-metadata"

      config = %{
        "bucket" => @test_bucket,
        "prefix" => prefix,
        "database_name" => "db",
        "table_name" => "tbl",
        "compression" => "none",
        "min_file_size_bytes" => 10_000_000
      }

      {:ok, state} = Iceberg.init(config)

      events = [Event.new(%{"_raw" => "metadata test", "_time" => 1_773_570_600})]
      {:ok, buffered} = Iceberg.send_batch(events, state)
      {:ok, _flushed} = Iceberg.flush(buffered)

      # Check manifest file exists
      {:ok, %{body: %{contents: meta_objects}}} =
        ExAws.S3.list_objects(@test_bucket, prefix: "#{prefix}/db/tbl/metadata/")
        |> ExAws.request()

      meta_keys = Enum.map(meta_objects, & &1.key)

      assert Enum.any?(meta_keys, &String.contains?(&1, "metadata.json"))
      assert Enum.any?(meta_keys, &String.contains?(&1, "manifests/"))
      assert Enum.any?(meta_keys, &String.contains?(&1, "snapshots/"))
    end
  end

  # ── Schema tracking ─────────────────────────────────────────────────

  describe "schema tracking" do
    test "infers schema from first batch" do
      config = %{
        "bucket" => @test_bucket,
        "prefix" => "iceberg-test-schema",
        "min_file_size_bytes" => 10_000_000
      }

      {:ok, state} = Iceberg.init(config)
      assert state.schema == []

      events = [
        Event.new(%{"_raw" => "test", "_time" => 1_000_000, "host" => "s1", "status" => 200})
      ]

      {:ok, new_state} = Iceberg.send_batch(events, state)
      field_names = Enum.map(new_state.schema, & &1.name)

      assert "host" in field_names
      assert "status" in field_names
      assert "_time" in field_names
    end

    test "evolves schema with new fields" do
      config = %{
        "bucket" => @test_bucket,
        "prefix" => "iceberg-test-schema-evolve",
        "min_file_size_bytes" => 10_000_000
      }

      {:ok, state} = Iceberg.init(config)

      batch1 = [Event.new(%{"_raw" => "t", "_time" => 1, "host" => "s1"})]
      {:ok, state2} = Iceberg.send_batch(batch1, state)

      batch2 = [Event.new(%{"_raw" => "t", "_time" => 2, "host" => "s1", "region" => "us-east-1"})]
      {:ok, state3} = Iceberg.send_batch(batch2, state2)

      field_names = Enum.map(state3.schema, & &1.name)
      assert "region" in field_names
      assert "host" in field_names
    end
  end

  # ── stop/1 ───────────────────────────────────────────────────────────

  describe "stop/1" do
    test "flushes remaining buffer on stop" do
      prefix = "iceberg-test-stop"

      config = %{
        "bucket" => @test_bucket,
        "prefix" => prefix,
        "database_name" => "db",
        "table_name" => "tbl",
        "compression" => "none",
        "min_file_size_bytes" => 10_000_000
      }

      {:ok, state} = Iceberg.init(config)
      events = [Event.new(%{"_raw" => "stop flush", "_time" => 1_773_570_600})]
      {:ok, buffered} = Iceberg.send_batch(events, state)

      assert :ok = Iceberg.stop(buffered)

      {:ok, %{body: %{contents: objects}}} =
        ExAws.S3.list_objects(@test_bucket, prefix: "#{prefix}/db/tbl/data/")
        |> ExAws.request()

      data_objects = Enum.reject(objects, fn o -> String.contains?(o.key, "metadata") end)
      assert length(data_objects) >= 1
    end
  end

  # ── healthy?/1 ──────────────────────────────────────────────────────

  describe "healthy?/1" do
    test "reports healthy" do
      {:ok, state} = Iceberg.init(%{"bucket" => @test_bucket, "prefix" => "iceberg-test-health"})
      assert Iceberg.healthy?(state) == true
    end
  end
end
