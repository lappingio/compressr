defmodule Compressr.Destination.S3Test do
  use ExUnit.Case, async: false

  alias Compressr.Destination.S3
  alias Compressr.Event

  @test_bucket "compressr-test-events"

  setup do
    # Clean up test bucket objects
    case ExAws.S3.list_objects(@test_bucket) |> ExAws.request() do
      {:ok, %{body: %{contents: objects}}} when is_list(objects) ->
        Enum.each(objects, fn obj ->
          ExAws.S3.delete_object(@test_bucket, obj.key) |> ExAws.request()
        end)

      _ ->
        :ok
    end

    :ok
  end

  describe "init/1" do
    test "initializes with valid config" do
      config = %{"bucket" => @test_bucket, "prefix" => "test-events"}
      assert {:ok, %S3{}} = S3.init(config)
    end

    test "returns error when bucket is missing" do
      assert {:error, :bucket_required} = S3.init(%{})
    end

    test "returns error when bucket is empty string" do
      assert {:error, :bucket_required} = S3.init(%{"bucket" => ""})
    end

    test "applies default config values" do
      config = %{"bucket" => @test_bucket}
      {:ok, state} = S3.init(config)

      assert state.prefix == "events"
      assert state.compression == :gzip
      assert state.storage_class == "STANDARD"
      assert state.file_close_interval_ms == 300_000
      assert state.max_file_size_bytes == 104_857_600
    end

    test "overrides defaults with provided config" do
      config = %{
        "bucket" => @test_bucket,
        "prefix" => "custom",
        "compression" => "none",
        "storage_class" => "GLACIER",
        "file_close_interval_ms" => 60_000,
        "max_file_size_bytes" => 1_000_000
      }

      {:ok, state} = S3.init(config)

      assert state.prefix == "custom"
      assert state.compression == :none
      assert state.storage_class == "GLACIER"
      assert state.file_close_interval_ms == 60_000
      assert state.max_file_size_bytes == 1_000_000
    end
  end

  describe "send_batch/2" do
    test "buffers events without flushing when under size limit" do
      config = %{"bucket" => @test_bucket, "prefix" => "test", "max_file_size_bytes" => 10_000_000}
      {:ok, state} = S3.init(config)

      events = [
        Event.new(%{"_raw" => "log line 1", "_time" => 1_000_000}),
        Event.new(%{"_raw" => "log line 2", "_time" => 1_000_001})
      ]

      {:ok, new_state} = S3.send_batch(events, state)
      assert length(new_state.buffer) == 2
      assert new_state.buffer_bytes > 0
    end

    test "auto-flushes to S3 when buffer exceeds max_file_size_bytes" do
      config = %{
        "bucket" => @test_bucket,
        "prefix" => "autoflush",
        "compression" => "none",
        "max_file_size_bytes" => 10
      }

      {:ok, state} = S3.init(config)

      events = [
        Event.new(%{"_raw" => "this is a longer log line that exceeds the tiny limit"}),
        Event.new(%{"_raw" => "another line"})
      ]

      {:ok, new_state} = S3.send_batch(events, state)
      # Buffer should be cleared after auto-flush
      assert new_state.buffer == []
      assert new_state.buffer_bytes == 0

      # Verify something was written to S3
      {:ok, %{body: %{contents: objects}}} =
        ExAws.S3.list_objects(@test_bucket, prefix: "autoflush/") |> ExAws.request()

      assert length(objects) >= 1
    end

    test "writes events as NDJSON format" do
      config = %{
        "bucket" => @test_bucket,
        "prefix" => "ndjson-test",
        "compression" => "none",
        "max_file_size_bytes" => 10
      }

      {:ok, state} = S3.init(config)

      events = [
        Event.new(%{"_raw" => "line1", "_time" => 1_700_000_000, "host" => "server1"}),
        Event.new(%{"_raw" => "line2", "_time" => 1_700_000_001, "host" => "server2"})
      ]

      {:ok, _state} = S3.send_batch(events, state)

      # Fetch the written object
      {:ok, %{body: %{contents: [object | _]}}} =
        ExAws.S3.list_objects(@test_bucket, prefix: "ndjson-test/") |> ExAws.request()

      {:ok, %{body: body}} =
        ExAws.S3.get_object(@test_bucket, object.key) |> ExAws.request()

      lines = String.split(body, "\n", trim: true)
      assert length(lines) == 2

      # Each line should be valid JSON
      Enum.each(lines, fn line ->
        assert {:ok, _} = Jason.decode(line)
      end)

      # Verify event content
      {:ok, first} = Jason.decode(Enum.at(lines, 0))
      assert first["_raw"] == "line1"
      assert first["host"] == "server1"
    end

    test "strips internal fields from events" do
      config = %{
        "bucket" => @test_bucket,
        "prefix" => "strip-test",
        "compression" => "none",
        "max_file_size_bytes" => 10
      }

      {:ok, state} = S3.init(config)

      event =
        Event.new(%{"_raw" => "test"})
        |> Compressr.Event.put_internal("__source_id", "src-1")

      {:ok, _state} = S3.send_batch([event], state)

      {:ok, %{body: %{contents: [object | _]}}} =
        ExAws.S3.list_objects(@test_bucket, prefix: "strip-test/") |> ExAws.request()

      {:ok, %{body: body}} =
        ExAws.S3.get_object(@test_bucket, object.key) |> ExAws.request()

      {:ok, parsed} = body |> String.trim() |> Jason.decode()
      refute Map.has_key?(parsed, "__source_id")
    end
  end

  describe "flush/1" do
    test "flushes buffered events to S3" do
      config = %{
        "bucket" => @test_bucket,
        "prefix" => "flush-test",
        "compression" => "none"
      }

      {:ok, state} = S3.init(config)
      events = [Event.new(%{"_raw" => "flush me"})]
      {:ok, buffered_state} = S3.send_batch(events, state)
      assert length(buffered_state.buffer) == 1

      {:ok, flushed_state} = S3.flush(buffered_state)
      assert flushed_state.buffer == []

      {:ok, %{body: %{contents: objects}}} =
        ExAws.S3.list_objects(@test_bucket, prefix: "flush-test/") |> ExAws.request()

      assert length(objects) == 1
    end

    test "flush with empty buffer is a no-op" do
      config = %{"bucket" => @test_bucket}
      {:ok, state} = S3.init(config)
      assert {:ok, ^state} = S3.flush(state)
    end
  end

  describe "file path convention" do
    test "uses date-partitioned path structure" do
      config = %{
        "bucket" => @test_bucket,
        "prefix" => "path-test",
        "compression" => "none",
        "max_file_size_bytes" => 10
      }

      {:ok, state} = S3.init(config)
      events = [Event.new(%{"_raw" => "path test event that is long enough"})]
      {:ok, _state} = S3.send_batch(events, state)

      {:ok, %{body: %{contents: [object | _]}}} =
        ExAws.S3.list_objects(@test_bucket, prefix: "path-test/") |> ExAws.request()

      # Verify path format: prefix/YYYY/MM/DD/HH/timestamp-uuid.ndjson
      parts = String.split(object.key, "/")
      assert Enum.at(parts, 0) == "path-test"
      # Year
      assert String.length(Enum.at(parts, 1)) == 4
      # Month
      assert String.length(Enum.at(parts, 2)) == 2
      # Day
      assert String.length(Enum.at(parts, 3)) == 2
      # Hour
      assert String.length(Enum.at(parts, 4)) == 2
      # Filename
      filename = Enum.at(parts, 5)
      assert String.ends_with?(filename, ".ndjson")
      assert String.contains?(filename, "-")
    end
  end

  describe "gzip compression" do
    test "compresses output with gzip by default" do
      config = %{
        "bucket" => @test_bucket,
        "prefix" => "gzip-test",
        "max_file_size_bytes" => 10
      }

      {:ok, state} = S3.init(config)
      events = [Event.new(%{"_raw" => "compressed event data that is long enough to trigger"})]
      {:ok, _state} = S3.send_batch(events, state)

      {:ok, %{body: %{contents: [object | _]}}} =
        ExAws.S3.list_objects(@test_bucket, prefix: "gzip-test/") |> ExAws.request()

      # Verify .gz extension
      assert String.ends_with?(object.key, ".ndjson.gz")

      # Verify the content is valid gzip
      {:ok, %{body: body}} =
        ExAws.S3.get_object(@test_bucket, object.key) |> ExAws.request()

      decompressed = :zlib.gunzip(body)
      lines = String.split(decompressed, "\n", trim: true)
      assert length(lines) == 1
      assert {:ok, parsed} = Jason.decode(Enum.at(lines, 0))
      assert parsed["_raw"] == "compressed event data that is long enough to trigger"
    end
  end

  describe "stop/1" do
    test "flushes remaining buffer on stop" do
      config = %{
        "bucket" => @test_bucket,
        "prefix" => "stop-test",
        "compression" => "none"
      }

      {:ok, state} = S3.init(config)
      events = [Event.new(%{"_raw" => "stop flush event"})]
      {:ok, buffered_state} = S3.send_batch(events, state)

      assert :ok = S3.stop(buffered_state)

      {:ok, %{body: %{contents: objects}}} =
        ExAws.S3.list_objects(@test_bucket, prefix: "stop-test/") |> ExAws.request()

      assert length(objects) == 1
    end
  end

  describe "healthy?/1" do
    test "reports healthy" do
      {:ok, state} = S3.init(%{"bucket" => @test_bucket})
      assert S3.healthy?(state) == true
    end
  end
end
