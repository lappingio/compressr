defmodule Compressr.Destination.Iceberg.MetadataTest do
  use ExUnit.Case, async: true

  alias Compressr.Destination.Iceberg.Metadata

  describe "generate_table_metadata/1" do
    test "generates metadata with format version 2" do
      meta = Metadata.generate_table_metadata(%{})
      assert meta["format-version"] == 2
    end

    test "generates metadata with UUID" do
      meta = Metadata.generate_table_metadata(%{})
      assert is_binary(meta["table-uuid"])
      assert String.length(meta["table-uuid"]) == 36  # UUID format
    end

    test "includes location from opts" do
      meta = Metadata.generate_table_metadata(%{location: "s3://bucket/path"})
      assert meta["location"] == "s3://bucket/path"
    end

    test "defaults location to empty string" do
      meta = Metadata.generate_table_metadata(%{})
      assert meta["location"] == ""
    end

    test "includes last-updated-ms as integer" do
      meta = Metadata.generate_table_metadata(%{})
      assert is_integer(meta["last-updated-ms"])
    end

    test "includes partition spec" do
      meta = Metadata.generate_table_metadata(%{})
      assert is_list(meta["partition-spec"])
      assert length(meta["partition-spec"]) == 1
    end

    test "includes empty snapshots list" do
      meta = Metadata.generate_table_metadata(%{})
      assert meta["snapshots"] == []
      assert meta["current-snapshot-id"] == -1
    end

    test "includes stub properties" do
      meta = Metadata.generate_table_metadata(%{})
      assert meta["properties"]["stub"] == "true"
      assert meta["properties"]["write.format.default"] == "ndjson-stub"
    end

    test "formats schema fields" do
      schema_fields = [
        %{name: "host", type: :string, nullable: false},
        %{name: "count", type: :integer, nullable: true}
      ]

      meta = Metadata.generate_table_metadata(%{schema: schema_fields})
      assert meta["last-column-id"] == 2
      assert is_list(meta["schema"])
      assert length(meta["schema"]) == 2

      [field1, field2] = meta["schema"]
      assert field1["name"] == "host"
      assert field1["required"] == true
      assert field1["type"] == "string"
      assert field2["name"] == "count"
      assert field2["required"] == false
      assert field2["type"] == "integer"
    end

    test "handles empty schema" do
      meta = Metadata.generate_table_metadata(%{schema: []})
      assert meta["schema"] == []
      assert meta["last-column-id"] == 0
    end
  end

  describe "generate_snapshot/1" do
    test "generates a snapshot with ID and timestamp" do
      snap = Metadata.generate_snapshot(%{})
      assert is_integer(snap["snapshot-id"])
      assert is_integer(snap["timestamp-ms"])
    end

    test "includes summary with operation type" do
      snap = Metadata.generate_snapshot(%{
        added_files: 5,
        added_records: 1000,
        total_records: 5000,
        total_files: 20
      })

      assert snap["summary"]["operation"] == "append"
      assert snap["summary"]["added-data-files"] == 5
      assert snap["summary"]["added-records"] == 1000
      assert snap["summary"]["total-records"] == 5000
      assert snap["summary"]["total-data-files"] == 20
    end

    test "includes manifest list path" do
      snap = Metadata.generate_snapshot(%{manifest_list_path: "s3://bucket/manifests/list.json"})
      assert snap["manifest-list"] == "s3://bucket/manifests/list.json"
    end

    test "defaults summary values to 0" do
      snap = Metadata.generate_snapshot(%{})
      assert snap["summary"]["added-data-files"] == 0
      assert snap["summary"]["added-records"] == 0
    end
  end

  describe "generate_manifest_entry/1" do
    test "generates a manifest entry" do
      entry = Metadata.generate_manifest_entry(%{
        file_path: "s3://bucket/data/file.ndjson",
        partition: %{"dt" => "2024-01-01"},
        record_count: 500,
        file_size_bytes: 1024 * 1024
      })

      assert entry["status"] == 1
      assert entry["data_file"]["file_path"] == "s3://bucket/data/file.ndjson"
      assert entry["data_file"]["file_format"] == "NDJSON_STUB"
      assert entry["data_file"]["partition"] == %{"dt" => "2024-01-01"}
      assert entry["data_file"]["record_count"] == 500
      assert entry["data_file"]["file_size_in_bytes"] == 1024 * 1024
    end

    test "defaults values when not provided" do
      entry = Metadata.generate_manifest_entry(%{})
      assert entry["data_file"]["file_path"] == ""
      assert entry["data_file"]["partition"] == %{}
      assert entry["data_file"]["record_count"] == 0
      assert entry["data_file"]["file_size_in_bytes"] == 0
    end
  end

  describe "generate_manifest/1" do
    test "generates a manifest with entries" do
      entries = [
        Metadata.generate_manifest_entry(%{file_path: "file1.json"}),
        Metadata.generate_manifest_entry(%{file_path: "file2.json"})
      ]

      manifest = Metadata.generate_manifest(entries)
      assert String.starts_with?(manifest["format"], "manifest-stub-v")
      assert length(manifest["entries"]) == 2
    end

    test "generates manifest with empty entries" do
      manifest = Metadata.generate_manifest([])
      assert manifest["entries"] == []
    end
  end
end
