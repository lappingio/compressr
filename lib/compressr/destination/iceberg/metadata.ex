defmodule Compressr.Destination.Iceberg.Metadata do
  @moduledoc """
  Stub metadata file generation for Iceberg tables.

  In a real Iceberg implementation, metadata is stored as Avro-serialised
  manifest files, manifest lists, and a `metadata.json` pointer. This
  module generates **JSON-based stubs** that mirror the structure so the
  file layout is Iceberg-compatible, but the content is not Avro and
  will not be readable by production Iceberg clients.

  When the real Parquet writer and `ex_iceberg` NIF are available, this
  module should be replaced with proper Iceberg metadata management.
  """

  @format_version 2

  @doc """
  Generate a table metadata JSON structure.

  This is the top-level `metadata.json` that Iceberg readers look for.
  """
  @spec generate_table_metadata(map()) :: map()
  def generate_table_metadata(opts) do
    now_ms = System.system_time(:millisecond)

    %{
      "format-version" => @format_version,
      "table-uuid" => uuid(),
      "location" => Map.get(opts, :location, ""),
      "last-updated-ms" => now_ms,
      "last-column-id" => length(Map.get(opts, :schema, [])),
      "schema" => format_schema(Map.get(opts, :schema, [])),
      "partition-spec" => [
        %{"source-id" => 1, "field-id" => 1000, "name" => "dt", "transform" => "identity"}
      ],
      "default-spec-id" => 0,
      "snapshots" => [],
      "current-snapshot-id" => -1,
      "properties" => %{
        "write.format.default" => "ndjson-stub",
        "stub" => "true"
      }
    }
  end

  @doc """
  Generate a snapshot record to be appended to the metadata snapshots list.

  A snapshot references a manifest list which in turn references manifest
  files that describe individual data files.
  """
  @spec generate_snapshot(map()) :: map()
  def generate_snapshot(opts) do
    now_ms = System.system_time(:millisecond)

    %{
      "snapshot-id" => :rand.uniform(1_000_000_000),
      "timestamp-ms" => now_ms,
      "summary" => %{
        "operation" => "append",
        "added-data-files" => Map.get(opts, :added_files, 0),
        "added-records" => Map.get(opts, :added_records, 0),
        "total-records" => Map.get(opts, :total_records, 0),
        "total-data-files" => Map.get(opts, :total_files, 0)
      },
      "manifest-list" => Map.get(opts, :manifest_list_path, "")
    }
  end

  @doc """
  Generate a manifest entry for a single data file.

  In real Iceberg this would be an Avro record inside a manifest file.
  We produce a JSON map instead.
  """
  @spec generate_manifest_entry(map()) :: map()
  def generate_manifest_entry(opts) do
    %{
      "status" => 1,
      "data_file" => %{
        "file_path" => Map.get(opts, :file_path, ""),
        "file_format" => "NDJSON_STUB",
        "partition" => Map.get(opts, :partition, %{}),
        "record_count" => Map.get(opts, :record_count, 0),
        "file_size_in_bytes" => Map.get(opts, :file_size_bytes, 0)
      }
    }
  end

  @doc """
  Generate a full manifest file (list of manifest entries) as a JSON structure.
  """
  @spec generate_manifest([map()]) :: map()
  def generate_manifest(entries) when is_list(entries) do
    %{
      "format" => "manifest-stub-v#{@format_version}",
      "entries" => entries
    }
  end

  # --- Private ---

  defp format_schema(fields) do
    fields
    |> Enum.with_index(1)
    |> Enum.map(fn {field, id} ->
      %{
        "id" => id,
        "name" => field.name,
        "required" => !field.nullable,
        "type" => Atom.to_string(field.type)
      }
    end)
  end

  defp uuid do
    <<a::32, b::16, c::16, d::16, e::48>> = :crypto.strong_rand_bytes(16)

    :io_lib.format(
      "~8.16.0b-~4.16.0b-~4.16.0b-~4.16.0b-~12.16.0b",
      [a, b, c, d, e]
    )
    |> IO.iodata_to_binary()
  end
end
