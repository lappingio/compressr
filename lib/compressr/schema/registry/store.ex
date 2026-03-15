defmodule Compressr.Schema.Registry.Store do
  @moduledoc ~S"""
  DynamoDB persistence for the schema registry.

  Persists log type records and schema versions using the same DynamoDB table
  as the existing schema store, with different pk/sk conventions:

    - Log types:      pk="log_type",       sk="{source_id}#{log_type_id}"
    - Schema versions: pk="schema_version", sk="{source_id}#{log_type_id}#{version}"
    - Field availability: pk="field_avail", sk="{source_id}#{log_type_id}#{field_name}"
  """

  alias Compressr.Schema.Registry.{LogType, SchemaVersion}

  # --- Log Type Persistence ---

  @doc """
  Save a log type record to DynamoDB.
  """
  @spec save_log_type(LogType.t()) :: :ok
  def save_log_type(%LogType{} = log_type) do
    item = %{
      "pk" => "log_type",
      "sk" => "#{log_type.source_id}##{log_type.id}",
      "id" => log_type.id,
      "name" => log_type.name,
      "source_id" => log_type.source_id,
      "fingerprint" => Base.encode64(log_type.fingerprint),
      "classification_method" => Atom.to_string(log_type.classification_method),
      "first_seen" => DateTime.to_iso8601(log_type.first_seen),
      "last_seen" => DateTime.to_iso8601(log_type.last_seen),
      "event_count" => Integer.to_string(log_type.event_count),
      "schema" => Jason.encode!(serialize_schema(log_type.schema))
    }

    ExAws.Dynamo.put_item(table_name(), item)
    |> ExAws.request!()

    :ok
  end

  @doc """
  Load all log types for a source from DynamoDB.
  """
  @spec load_log_types(String.t()) :: {:ok, [LogType.t()]}
  def load_log_types(source_id) do
    result =
      ExAws.Dynamo.query(table_name(),
        key_condition_expression: "pk = :pk AND begins_with(sk, :sk_prefix)",
        expression_attribute_values: [pk: "log_type", sk_prefix: "#{source_id}#"]
      )
      |> ExAws.request!()

    log_types =
      result
      |> Map.get("Items", [])
      |> Enum.map(&item_to_log_type/1)

    {:ok, log_types}
  end

  @doc """
  Load a specific log type for a source from DynamoDB.
  """
  @spec load_log_type(String.t(), String.t()) :: {:ok, LogType.t()} | {:ok, nil}
  def load_log_type(source_id, log_type_id) do
    result =
      ExAws.Dynamo.get_item(table_name(), %{
        "pk" => "log_type",
        "sk" => "#{source_id}##{log_type_id}"
      })
      |> ExAws.request!()

    case result do
      %{"Item" => item} when map_size(item) > 0 ->
        {:ok, item_to_log_type(item)}

      _ ->
        {:ok, nil}
    end
  end

  # --- Schema Version Persistence ---

  @doc """
  Save a schema version record to DynamoDB.
  """
  @spec save_schema_version(SchemaVersion.t()) :: :ok
  def save_schema_version(%SchemaVersion{} = version) do
    item = %{
      "pk" => "schema_version",
      "sk" => "#{version.source_id}##{version.log_type_id}##{pad_version(version.version)}",
      "version" => Integer.to_string(version.version),
      "log_type_id" => version.log_type_id,
      "source_id" => version.source_id,
      "timestamp" => DateTime.to_iso8601(version.timestamp),
      "fields_added" => Jason.encode!(version.fields_added),
      "fields_removed" => Jason.encode!(version.fields_removed),
      "type_changes" => Jason.encode!(serialize_type_changes(version.type_changes)),
      "schema" => Jason.encode!(serialize_schema(version.schema))
    }

    ExAws.Dynamo.put_item(table_name(), item)
    |> ExAws.request!()

    :ok
  end

  @doc """
  Load all schema versions for a log type from DynamoDB.
  """
  @spec load_schema_versions(String.t(), String.t()) :: {:ok, [SchemaVersion.t()]}
  def load_schema_versions(source_id, log_type_id) do
    result =
      ExAws.Dynamo.query(table_name(),
        key_condition_expression: "pk = :pk AND begins_with(sk, :sk_prefix)",
        expression_attribute_values: [
          pk: "schema_version",
          sk_prefix: "#{source_id}##{log_type_id}#"
        ]
      )
      |> ExAws.request!()

    versions =
      result
      |> Map.get("Items", [])
      |> Enum.map(&item_to_schema_version/1)
      |> Enum.sort_by(& &1.version)

    {:ok, versions}
  end

  # --- Field Availability ---

  @doc """
  Save field availability (first_seen timestamp) for a field in a log type.
  """
  @spec save_field_availability(String.t(), String.t(), String.t(), DateTime.t()) :: :ok
  def save_field_availability(source_id, log_type_id, field_name, first_seen) do
    item = %{
      "pk" => "field_avail",
      "sk" => "#{source_id}##{log_type_id}##{field_name}",
      "source_id" => source_id,
      "log_type_id" => log_type_id,
      "field_name" => field_name,
      "first_seen" => DateTime.to_iso8601(first_seen)
    }

    ExAws.Dynamo.put_item(table_name(), item)
    |> ExAws.request!()

    :ok
  end

  @doc """
  Load field availability for a specific field across a source.

  Returns a list of `%{source_id, log_type_id, field_name, first_seen}` maps.
  """
  @spec load_field_availability(String.t(), String.t()) :: {:ok, [map()]}
  def load_field_availability(source_id, field_name) do
    # We need to scan for field_avail items matching this source and field
    # Since we can't do a contains query on sort key, we query by source prefix
    # and filter by field_name
    result =
      ExAws.Dynamo.query(table_name(),
        key_condition_expression: "pk = :pk AND begins_with(sk, :sk_prefix)",
        expression_attribute_values: [
          pk: "field_avail",
          sk_prefix: "#{source_id}#"
        ]
      )
      |> ExAws.request!()

    availabilities =
      result
      |> Map.get("Items", [])
      |> Enum.filter(fn item -> get_s(item, "field_name") == field_name end)
      |> Enum.map(fn item ->
        %{
          source_id: get_s(item, "source_id"),
          log_type_id: get_s(item, "log_type_id"),
          field_name: get_s(item, "field_name"),
          first_seen: parse_datetime(get_s(item, "first_seen"))
        }
      end)

    {:ok, availabilities}
  end

  # --- Private ---

  defp pad_version(version) do
    version
    |> Integer.to_string()
    |> String.pad_leading(10, "0")
  end

  defp serialize_schema(schema) when is_map(schema) do
    schema
    |> Enum.map(fn {field_name, info} ->
      {field_name, %{
        "type" => Atom.to_string(info.type),
        "first_seen" => DateTime.to_iso8601(info.first_seen),
        "sample_values" => inspect(info.sample_values)
      }}
    end)
    |> Map.new()
  end

  defp deserialize_schema(json) do
    case Jason.decode(json) do
      {:ok, map} ->
        map
        |> Enum.map(fn {field_name, info} ->
          {field_name, %{
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

  defp serialize_type_changes(type_changes) do
    Enum.map(type_changes, fn {field, old_type, new_type} ->
      %{"field" => field, "old_type" => Atom.to_string(old_type), "new_type" => Atom.to_string(new_type)}
    end)
  end

  defp deserialize_type_changes(json) do
    case Jason.decode(json) do
      {:ok, list} when is_list(list) ->
        Enum.map(list, fn %{"field" => f, "old_type" => ot, "new_type" => nt} ->
          {f, String.to_existing_atom(ot), String.to_existing_atom(nt)}
        end)

      _ ->
        []
    end
  end

  defp item_to_log_type(item) do
    %LogType{
      id: get_s(item, "id"),
      name: get_s(item, "name"),
      source_id: get_s(item, "source_id"),
      fingerprint: Base.decode64!(get_s(item, "fingerprint")),
      classification_method: String.to_existing_atom(get_s(item, "classification_method")),
      first_seen: parse_datetime(get_s(item, "first_seen")),
      last_seen: parse_datetime(get_s(item, "last_seen")),
      event_count: String.to_integer(get_s(item, "event_count")),
      schema: deserialize_schema(get_s(item, "schema"))
    }
  end

  defp item_to_schema_version(item) do
    %SchemaVersion{
      version: String.to_integer(get_s(item, "version")),
      log_type_id: get_s(item, "log_type_id"),
      source_id: get_s(item, "source_id"),
      timestamp: parse_datetime(get_s(item, "timestamp")),
      fields_added: Jason.decode!(get_s(item, "fields_added")),
      fields_removed: Jason.decode!(get_s(item, "fields_removed")),
      type_changes: deserialize_type_changes(get_s(item, "type_changes")),
      schema: deserialize_schema(get_s(item, "schema"))
    }
  end

  defp parse_datetime(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> dt
      _ -> DateTime.utc_now()
    end
  end

  defp parse_datetime(_), do: DateTime.utc_now()

  defp get_s(item, key) do
    case Map.get(item, key) do
      %{"S" => val} -> val
      val when is_binary(val) -> val
      _ -> nil
    end
  end

  defp table_name do
    prefix = Application.get_env(:compressr, :dynamodb_table_prefix, "compressr_")
    "#{prefix}schemas"
  end
end
