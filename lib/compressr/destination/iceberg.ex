defmodule Compressr.Destination.Iceberg do
  @moduledoc """
  Iceberg destination implementation (stub / simulation).

  Writes events as gzip-compressed NDJSON files organised in an
  Iceberg-compatible partition layout on S3.  Generates JSON-based
  metadata stubs that mirror the Iceberg metadata structure.

  **This is a simulation layer.**  Real Iceberg integration requires:

    * A Parquet writer (Rust NIF via `ex_iceberg`)
    * Proper Avro-based metadata (manifests, manifest lists, snapshots)
    * AWS Glue Catalog registration

  Those concerns are isolated behind clear seams so they can be swapped
  in without changing the destination's public API.

  ## Configuration

    * `bucket` — S3 bucket name (required)
    * `prefix` — Key prefix for the table location (default: `"iceberg"`)
    * `region` — AWS region (default: `"us-east-1"`)
    * `database_name` — Logical database / namespace (default: `"default"`)
    * `table_name` — Iceberg table name (default: `"events"`)
    * `partition_by` — `:daily` or `:hourly` (default: `:daily`)
    * `compression` — `:gzip`, `:none` (default: `:gzip`).
      `:snappy` and `:zstd` are accepted but fall back to `:gzip` in
      stub mode since NDJSON does not support those codecs natively.
    * `storage_class` — S3 storage class (default: `"INTELLIGENT_TIERING"`)
    * `min_file_size_bytes` — Minimum uncompressed buffer size before
      closing a file (default: 52_428_800 = 50 MB)
    * `file_close_interval_ms` — Maximum time to keep a file open
      (default: 300_000 = 5 min)
  """

  @behaviour Compressr.Destination

  alias Compressr.Destination.Iceberg.{Metadata, Partition, SchemaManager}

  @default_config %{
    "prefix" => "iceberg",
    "region" => "us-east-1",
    "database_name" => "default",
    "table_name" => "events",
    "partition_by" => "daily",
    "compression" => "gzip",
    "storage_class" => "INTELLIGENT_TIERING",
    "min_file_size_bytes" => 52_428_800,
    "file_close_interval_ms" => 300_000
  }

  defstruct [
    :bucket,
    :prefix,
    :region,
    :database_name,
    :table_name,
    :partition_by,
    :compression,
    :storage_class,
    :min_file_size_bytes,
    :file_close_interval_ms,
    # partition_value => %{lines: [String.t()], bytes: non_neg_integer(), row_count: non_neg_integer()}
    partition_buffers: %{},
    schema: [],
    total_records: 0,
    total_files: 0,
    snapshots: []
  ]

  # ── Behaviour callbacks ──────────────────────────────────────────────

  @impl true
  def init(config) do
    config = Map.merge(@default_config, config)
    bucket = Map.get(config, "bucket")

    if is_nil(bucket) or bucket == "" do
      {:error, :bucket_required}
    else
      state = %__MODULE__{
        bucket: bucket,
        prefix: Map.get(config, "prefix", "iceberg"),
        region: Map.get(config, "region", "us-east-1"),
        database_name: Map.get(config, "database_name", "default"),
        table_name: Map.get(config, "table_name", "events"),
        partition_by: parse_partition_by(Map.get(config, "partition_by", "daily")),
        compression: parse_compression(Map.get(config, "compression", "gzip")),
        storage_class: Map.get(config, "storage_class", "INTELLIGENT_TIERING"),
        min_file_size_bytes: Map.get(config, "min_file_size_bytes", 52_428_800),
        file_close_interval_ms: Map.get(config, "file_close_interval_ms", 300_000)
      }

      # Write initial table metadata stub
      write_table_metadata(state)

      {:ok, state}
    end
  end

  @impl true
  def send_batch(events, %__MODULE__{} = state) when is_list(events) do
    # Evolve schema with new events
    {_status, new_schema, _new_fields} =
      if state.schema == [] do
        {:ok, SchemaManager.infer_schema(events), SchemaManager.infer_schema(events)}
      else
        SchemaManager.evolve_schema(state.schema, events)
      end

    # Partition events and buffer them
    state = %{state | schema: new_schema}

    state =
      Enum.reduce(events, state, fn event, acc ->
        pv = Partition.partition_value(event, acc.partition_by)
        external = Compressr.Event.to_external_map(event)

        line =
          case Jason.encode(external) do
            {:ok, json} -> json
            {:error, _} -> Jason.encode!(%{"_raw" => inspect(external)})
          end

        line_bytes = byte_size(line) + 1

        buf = Map.get(acc.partition_buffers, pv, %{lines: [], bytes: 0, row_count: 0})

        buf = %{
          buf
          | lines: buf.lines ++ [line],
            bytes: buf.bytes + line_bytes,
            row_count: buf.row_count + 1
        }

        %{acc | partition_buffers: Map.put(acc.partition_buffers, pv, buf)}
      end)

    # Flush any partitions that have exceeded the minimum file size
    flush_full_partitions(state)
  end

  @impl true
  def flush(%__MODULE__{partition_buffers: bufs} = state) when bufs == %{}, do: {:ok, state}

  def flush(%__MODULE__{} = state) do
    flush_all_partitions(state)
  end

  @impl true
  def stop(%__MODULE__{} = state) do
    if state.partition_buffers != %{} do
      flush_all_partitions(state)
    end

    :ok
  end

  @impl true
  def healthy?(%__MODULE__{}), do: true

  # ── Internal helpers ─────────────────────────────────────────────────

  defp flush_full_partitions(state) do
    {to_flush, to_keep} =
      Enum.split_with(state.partition_buffers, fn {_pv, buf} ->
        buf.bytes >= state.min_file_size_bytes
      end)

    if to_flush == [] do
      {:ok, state}
    else
      state = %{state | partition_buffers: Map.new(to_keep)}
      do_flush_partitions(state, to_flush)
    end
  end

  defp flush_all_partitions(state) do
    partitions = Enum.to_list(state.partition_buffers)
    state = %{state | partition_buffers: %{}}
    do_flush_partitions(state, partitions)
  end

  defp do_flush_partitions(state, partitions) do
    Enum.reduce(partitions, {:ok, state}, fn
      {_pv, %{lines: []}}, {:ok, acc} ->
        {:ok, acc}

      {pv, buf}, {:ok, acc} ->
        case upload_partition(acc, pv, buf) do
          {:ok, new_acc} -> {:ok, new_acc}
          {:error, reason} -> {:error, reason, acc}
        end

      _partition, error ->
        error
    end)
  end

  defp upload_partition(state, partition_value, buf) do
    ndjson = Enum.join(buf.lines, "\n") <> "\n"

    {body, extension} =
      case state.compression do
        :gzip -> {:zlib.gzip(ndjson), ".ndjson.gz"}
        :none -> {ndjson, ".ndjson"}
      end

    data_dir =
      Partition.data_prefix(state.prefix, state.database_name, state.table_name, partition_value)

    uuid = Base.url_encode64(:crypto.strong_rand_bytes(8), padding: false)
    timestamp = System.system_time(:millisecond) |> Integer.to_string()
    key = "#{data_dir}/#{timestamp}-#{uuid}#{extension}"

    opts =
      [content_type: content_type(state.compression)] ++
        storage_class_opt(state.storage_class)

    request = ExAws.S3.put_object(state.bucket, key, body, opts)

    case ExAws.request(request) do
      {:ok, _} ->
        # Record file metadata and create a snapshot stub
        manifest_entry =
          Metadata.generate_manifest_entry(%{
            file_path: "s3://#{state.bucket}/#{key}",
            partition: %{"dt" => partition_value},
            record_count: buf.row_count,
            file_size_bytes: byte_size(body)
          })

        snapshot =
          Metadata.generate_snapshot(%{
            added_files: 1,
            added_records: buf.row_count,
            total_records: state.total_records + buf.row_count,
            total_files: state.total_files + 1,
            manifest_list_path: manifest_list_key(state)
          })

        new_state = %{
          state
          | total_records: state.total_records + buf.row_count,
            total_files: state.total_files + 1,
            snapshots: state.snapshots ++ [%{snapshot: snapshot, manifest_entry: manifest_entry}]
        }

        # Write updated metadata to S3 (best-effort)
        write_snapshot_metadata(new_state, snapshot, manifest_entry)

        {:ok, new_state}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp write_table_metadata(state) do
    location = "s3://#{state.bucket}/#{state.prefix}/#{state.database_name}/#{state.table_name}"

    meta =
      Metadata.generate_table_metadata(%{
        location: location,
        schema: state.schema
      })

    key = metadata_key(state, "metadata.json")

    case Jason.encode(meta, pretty: true) do
      {:ok, json} ->
        ExAws.S3.put_object(state.bucket, key, json, content_type: "application/json")
        |> ExAws.request()

      _ ->
        :ok
    end
  end

  defp write_snapshot_metadata(state, snapshot, manifest_entry) do
    # Write manifest file
    manifest = Metadata.generate_manifest([manifest_entry])
    manifest_key = metadata_key(state, "manifests/manifest-#{state.total_files}.json")

    with {:ok, manifest_json} <- Jason.encode(manifest, pretty: true) do
      ExAws.S3.put_object(state.bucket, manifest_key, manifest_json,
        content_type: "application/json"
      )
      |> ExAws.request()
    end

    # Write snapshot to the snapshots directory
    snap_key = metadata_key(state, "snapshots/snap-#{state.total_files}.json")

    with {:ok, snap_json} <- Jason.encode(snapshot, pretty: true) do
      ExAws.S3.put_object(state.bucket, snap_key, snap_json, content_type: "application/json")
      |> ExAws.request()
    end

    :ok
  end

  defp metadata_key(state, suffix) do
    "#{state.prefix}/#{state.database_name}/#{state.table_name}/metadata/#{suffix}"
  end

  defp manifest_list_key(state) do
    "s3://#{state.bucket}/#{metadata_key(state, "manifests")}"
  end

  defp content_type(:gzip), do: "application/gzip"
  defp content_type(:none), do: "application/x-ndjson"

  defp storage_class_opt("STANDARD"), do: []
  defp storage_class_opt("INTELLIGENT_TIERING"), do: [storage_class: "INTELLIGENT_TIERING"]
  defp storage_class_opt(class), do: [storage_class: class]

  defp parse_partition_by("daily"), do: :daily
  defp parse_partition_by(:daily), do: :daily
  defp parse_partition_by("hourly"), do: :hourly
  defp parse_partition_by(:hourly), do: :hourly
  defp parse_partition_by(_), do: :daily

  # In stub mode, snappy and zstd fall back to gzip since NDJSON
  # doesn't natively support those codecs.
  defp parse_compression("gzip"), do: :gzip
  defp parse_compression(:gzip), do: :gzip
  defp parse_compression("none"), do: :none
  defp parse_compression(:none), do: :none
  defp parse_compression("snappy"), do: :gzip
  defp parse_compression(:snappy), do: :gzip
  defp parse_compression("zstd"), do: :gzip
  defp parse_compression(:zstd), do: :gzip
  defp parse_compression(_), do: :gzip
end
