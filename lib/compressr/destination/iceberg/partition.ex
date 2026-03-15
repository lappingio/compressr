defmodule Compressr.Destination.Iceberg.Partition do
  @moduledoc """
  Partition management for Iceberg-style table layouts.

  Extracts partition values from event timestamps and generates
  partition directory paths compatible with Iceberg's identity
  partition transforms.
  """

  @doc """
  Extract a partition value from an event's `_time` field.

  ## Partition granularity

    * `:daily`  — "2026-03-15"
    * `:hourly` — "2026-03-15-14"

  The `_time` field is expected to be a Unix epoch timestamp in seconds.
  """
  @spec partition_value(map(), :daily | :hourly) :: String.t()
  def partition_value(event, partition_by) do
    timestamp = Map.get(event, "_time", 0)
    dt = DateTime.from_unix!(timestamp, :second)

    case partition_by do
      :daily ->
        Date.to_string(DateTime.to_date(dt))

      :hourly ->
        date = Date.to_string(DateTime.to_date(dt))
        hour = dt.hour |> Integer.to_string() |> String.pad_leading(2, "0")
        "#{date}-#{hour}"
    end
  end

  @doc """
  Generate the partition directory path segment for a given partition value.

  Returns a path like `dt=2026-03-15` or `dt=2026-03-15-14`.
  """
  @spec partition_path(String.t()) :: String.t()
  def partition_path(value) do
    "dt=#{value}"
  end

  @doc """
  Build the full data path for an Iceberg-style table layout.

  Format: `{prefix}/{database}/{table}/data/{partition_field}={value}`
  """
  @spec data_prefix(String.t(), String.t(), String.t(), String.t()) :: String.t()
  def data_prefix(prefix, database, table, partition_value) do
    partition_dir = partition_path(partition_value)
    "#{prefix}/#{database}/#{table}/data/#{partition_dir}"
  end
end
