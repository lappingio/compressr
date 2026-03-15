defmodule Compressr.Destination.S3 do
  @moduledoc """
  S3 destination implementation.

  Batches events and writes them to S3 as NDJSON files with optional gzip
  compression. Supports configurable file close conditions based on time
  interval and file size.

  ## Configuration

    * `bucket` - S3 bucket name (required)
    * `prefix` - Key prefix for objects (default: "events")
    * `region` - AWS region (default: "us-east-1")
    * `compression` - `:gzip` or `:none` (default: `:gzip`)
    * `storage_class` - S3 storage class (default: "STANDARD")
    * `file_close_interval_ms` - Max time before flushing, in ms (default: 300_000)
    * `max_file_size_bytes` - Max uncompressed size before flushing (default: 104_857_600)
  """

  @behaviour Compressr.Destination

  @default_config %{
    "prefix" => "events",
    "region" => "us-east-1",
    "compression" => "gzip",
    "storage_class" => "STANDARD",
    "file_close_interval_ms" => 300_000,
    "max_file_size_bytes" => 104_857_600
  }

  defstruct [
    :bucket,
    :prefix,
    :region,
    :compression,
    :storage_class,
    :file_close_interval_ms,
    :max_file_size_bytes,
    buffer: [],
    buffer_bytes: 0
  ]

  @impl true
  def init(config) do
    config = Map.merge(@default_config, config)

    bucket = Map.get(config, "bucket")

    if is_nil(bucket) or bucket == "" do
      {:error, :bucket_required}
    else
      state = %__MODULE__{
        bucket: bucket,
        prefix: Map.get(config, "prefix", "events"),
        region: Map.get(config, "region", "us-east-1"),
        compression: parse_compression(Map.get(config, "compression", "gzip")),
        storage_class: Map.get(config, "storage_class", "STANDARD"),
        file_close_interval_ms: Map.get(config, "file_close_interval_ms", 300_000),
        max_file_size_bytes: Map.get(config, "max_file_size_bytes", 104_857_600),
        buffer: [],
        buffer_bytes: 0
      }

      {:ok, state}
    end
  end

  @impl true
  def send_batch(events, %__MODULE__{} = state) when is_list(events) do
    lines =
      Enum.map(events, fn event ->
        external = Compressr.Event.to_external_map(event)

        case Jason.encode(external) do
          {:ok, json} -> json
          {:error, _} -> Jason.encode!(%{"_raw" => inspect(external)})
        end
      end)

    new_bytes = Enum.reduce(lines, 0, fn line, acc -> acc + byte_size(line) + 1 end)

    new_state = %{
      state
      | buffer: state.buffer ++ lines,
        buffer_bytes: state.buffer_bytes + new_bytes
    }

    if new_state.buffer_bytes >= new_state.max_file_size_bytes do
      do_flush(new_state)
    else
      {:ok, new_state}
    end
  end

  @impl true
  def flush(%__MODULE__{buffer: []} = state), do: {:ok, state}

  def flush(%__MODULE__{} = state) do
    do_flush(state)
  end

  @impl true
  def stop(%__MODULE__{} = state) do
    if state.buffer != [] do
      do_flush(state)
    end

    :ok
  end

  @impl true
  def healthy?(%__MODULE__{}), do: true

  # --- Internal ---

  defp do_flush(%__MODULE__{buffer: []} = state), do: {:ok, state}

  defp do_flush(%__MODULE__{} = state) do
    ndjson = Enum.join(state.buffer, "\n") <> "\n"

    {body, extension} =
      case state.compression do
        :gzip -> {:zlib.gzip(ndjson), ".ndjson.gz"}
        :none -> {ndjson, ".ndjson"}
      end

    key = build_key(state.prefix, extension)

    opts =
      [
        content_type: content_type(state.compression)
      ] ++ storage_class_opt(state.storage_class)

    request = ExAws.S3.put_object(state.bucket, key, body, opts)

    case ExAws.request(request) do
      {:ok, _} ->
        {:ok, %{state | buffer: [], buffer_bytes: 0}}

      {:error, reason} ->
        {:error, reason, state}
    end
  end

  defp build_key(prefix, extension) do
    now = DateTime.utc_now()
    uuid = Base.url_encode64(:crypto.strong_rand_bytes(8), padding: false)

    timestamp =
      now
      |> DateTime.to_unix(:millisecond)
      |> Integer.to_string()

    year = now.year |> Integer.to_string() |> String.pad_leading(4, "0")
    month = now.month |> Integer.to_string() |> String.pad_leading(2, "0")
    day = now.day |> Integer.to_string() |> String.pad_leading(2, "0")
    hour = now.hour |> Integer.to_string() |> String.pad_leading(2, "0")

    "#{prefix}/#{year}/#{month}/#{day}/#{hour}/#{timestamp}-#{uuid}#{extension}"
  end

  defp content_type(:gzip), do: "application/gzip"
  defp content_type(:none), do: "application/x-ndjson"

  defp storage_class_opt("STANDARD"), do: []
  defp storage_class_opt(class), do: [storage_class: class]

  defp parse_compression("gzip"), do: :gzip
  defp parse_compression(:gzip), do: :gzip
  defp parse_compression("none"), do: :none
  defp parse_compression(:none), do: :none
  defp parse_compression(_), do: :gzip
end
