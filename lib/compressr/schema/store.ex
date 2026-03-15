defmodule Compressr.Schema.Store do
  @moduledoc """
  DynamoDB persistence for learned schemas and drift events.

  Schemas are stored with:
    pk = "schema"
    sk = "\#{source_id}"

  Drift events are stored with:
    pk = "drift"
    sk = "\#{source_id}#\#{timestamp}"
  """

  alias Compressr.Schema.DriftEvent

  @doc """
  Save a learned schema for a source.
  """
  @spec save_schema(String.t(), map(), binary()) :: :ok
  def save_schema(source_id, schema, fingerprint) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    # Serialize schema field info to JSON-safe format
    serialized_schema =
      schema
      |> Enum.map(fn {field_name, info} ->
        {field_name,
         %{
           "type" => Atom.to_string(info.type),
           "first_seen" => DateTime.to_iso8601(info.first_seen),
           "sample_values" => inspect(info.sample_values)
         }}
      end)
      |> Map.new()

    item = %{
      "pk" => "schema",
      "sk" => source_id,
      "schema" => Jason.encode!(serialized_schema),
      "fingerprint" => Base.encode64(fingerprint),
      "updated_at" => now
    }

    ExAws.Dynamo.put_item(table_name(), item)
    |> ExAws.request!()

    :ok
  end

  @doc """
  Load a learned schema for a source.

  Returns `{:ok, {schema, fingerprint}}` if found, `{:ok, nil}` if not.
  """
  @spec load_schema(String.t()) :: {:ok, {map(), binary()} | nil}
  def load_schema(source_id) do
    result =
      ExAws.Dynamo.get_item(table_name(), %{"pk" => "schema", "sk" => source_id})
      |> ExAws.request!()

    case result do
      %{"Item" => item} when map_size(item) > 0 ->
        schema_json = get_s(item, "schema")
        fingerprint_b64 = get_s(item, "fingerprint")

        schema = deserialize_schema(schema_json)
        fingerprint = Base.decode64!(fingerprint_b64)

        {:ok, {schema, fingerprint}}

      _ ->
        {:ok, nil}
    end
  end

  @doc """
  Save a drift event.
  """
  @spec save_drift_event(DriftEvent.t()) :: :ok
  def save_drift_event(%DriftEvent{} = drift_event) do
    timestamp_str = DateTime.to_iso8601(drift_event.timestamp)

    item = %{
      "pk" => "drift",
      "sk" => "#{drift_event.source_id}##{timestamp_str}",
      "source_id" => drift_event.source_id,
      "timestamp" => timestamp_str,
      "drift_type" => Atom.to_string(drift_event.drift_type),
      "field_name" => drift_event.field_name,
      "old_value" => inspect(drift_event.old_value),
      "new_value" => inspect(drift_event.new_value)
    }

    item =
      if drift_event.sample_event do
        Map.put(item, "sample_event", Jason.encode!(drift_event.sample_event))
      else
        item
      end

    ExAws.Dynamo.put_item(table_name(), item)
    |> ExAws.request!()

    :ok
  end

  @doc """
  Load drift events for a source, ordered by timestamp.
  """
  @spec load_drift_events(String.t()) :: {:ok, [DriftEvent.t()]}
  def load_drift_events(source_id) do
    result =
      ExAws.Dynamo.query(table_name(),
        key_condition_expression: "pk = :pk AND begins_with(sk, :sk_prefix)",
        expression_attribute_values: [pk: "drift", sk_prefix: "#{source_id}#"]
      )
      |> ExAws.request!()

    events =
      result
      |> Map.get("Items", [])
      |> Enum.map(&item_to_drift_event/1)

    {:ok, events}
  end

  # --- Private ---

  defp deserialize_schema(json) do
    case Jason.decode(json) do
      {:ok, map} ->
        map
        |> Enum.map(fn {field_name, info} ->
          {field_name,
           %{
             type: String.to_existing_atom(info["type"]),
             first_seen: parse_datetime(info["first_seen"]),
             sample_values: []
           }}
        end)
        |> Map.new()

      _ ->
        %{}
    end
  end

  defp parse_datetime(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> dt
      _ -> DateTime.utc_now()
    end
  end

  defp parse_datetime(_), do: DateTime.utc_now()

  defp item_to_drift_event(item) do
    %DriftEvent{
      source_id: get_s(item, "source_id"),
      timestamp: parse_datetime(get_s(item, "timestamp")),
      drift_type: String.to_existing_atom(get_s(item, "drift_type")),
      field_name: get_s(item, "field_name"),
      old_value: get_s(item, "old_value"),
      new_value: get_s(item, "new_value"),
      sample_event: decode_sample_event(get_s(item, "sample_event"))
    }
  end

  defp decode_sample_event(nil), do: nil

  defp decode_sample_event(json) do
    case Jason.decode(json) do
      {:ok, map} -> map
      _ -> nil
    end
  end

  defp get_s(item, key) do
    case Map.get(item, key) do
      %{"S" => val} -> val
      _ -> nil
    end
  end

  defp table_name do
    prefix = Application.get_env(:compressr, :dynamodb_table_prefix, "compressr_")
    "#{prefix}schemas"
  end
end
