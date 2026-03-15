defmodule Compressr.Schema.Registry.SchemaVersion do
  @moduledoc """
  Schema version tracking for log types.

  Each time a log type's schema changes (new fields, removed fields, type
  changes), a new version record is created capturing the diff. This enables
  schema evolution timeline and field availability queries.
  """

  @type t :: %__MODULE__{
          version: non_neg_integer(),
          log_type_id: String.t(),
          source_id: String.t(),
          timestamp: DateTime.t(),
          fields_added: [String.t()],
          fields_removed: [String.t()],
          type_changes: [{String.t(), atom(), atom()}],
          schema: map()
        }

  @enforce_keys [:version, :log_type_id, :source_id]
  defstruct [
    :version,
    :log_type_id,
    :source_id,
    timestamp: nil,
    fields_added: [],
    fields_removed: [],
    type_changes: [],
    schema: %{}
  ]

  @doc """
  Create a new schema version by diffing old and new schemas.

  Returns a `%SchemaVersion{}` struct with the diff details. If `old_schema`
  is nil or empty, all fields in `new_schema` are treated as added.

  ## Parameters

    * `log_type_id` - the log type this version belongs to
    * `source_id` - the source this log type belongs to
    * `old_schema` - the previous schema (map of field_name => field_info), or nil
    * `new_schema` - the new schema (map of field_name => field_info)
    * `version` - the version number for this record

  """
  @spec create_version(String.t(), String.t(), map() | nil, map(), non_neg_integer()) :: t()
  def create_version(log_type_id, source_id, old_schema, new_schema, version) do
    old_schema = old_schema || %{}

    old_keys = MapSet.new(Map.keys(old_schema))
    new_keys = MapSet.new(Map.keys(new_schema))

    fields_added =
      new_keys
      |> MapSet.difference(old_keys)
      |> MapSet.to_list()
      |> Enum.sort()

    fields_removed =
      old_keys
      |> MapSet.difference(new_keys)
      |> MapSet.to_list()
      |> Enum.sort()

    type_changes =
      old_keys
      |> MapSet.intersection(new_keys)
      |> Enum.flat_map(fn field ->
        old_type = get_field_type(old_schema, field)
        new_type = get_field_type(new_schema, field)

        if old_type != new_type do
          [{field, old_type, new_type}]
        else
          []
        end
      end)
      |> Enum.sort()

    %__MODULE__{
      version: version,
      log_type_id: log_type_id,
      source_id: source_id,
      timestamp: DateTime.utc_now(),
      fields_added: fields_added,
      fields_removed: fields_removed,
      type_changes: type_changes,
      schema: new_schema
    }
  end

  @doc """
  Get the availability of a specific field across a list of schema versions.

  Returns `{:ok, %{first_seen: DateTime.t()}}` if the field was found in any
  version, or `:not_found` if the field was never seen.
  """
  @spec get_field_availability([t()], String.t()) :: {:ok, %{first_seen: DateTime.t()}} | :not_found
  def get_field_availability(versions, field_name) when is_list(versions) do
    versions
    |> Enum.sort_by(& &1.version)
    |> Enum.reduce_while(:not_found, fn version, _acc ->
      if field_name in version.fields_added do
        {:halt, {:ok, %{first_seen: version.timestamp}}}
      else
        # Check if field exists in the schema of the first version (initial schema)
        if version.version == 1 and Map.has_key?(version.schema, field_name) do
          {:halt, {:ok, %{first_seen: version.timestamp}}}
        else
          {:cont, :not_found}
        end
      end
    end)
  end

  # --- Private ---

  defp get_field_type(schema, field) do
    case Map.get(schema, field) do
      %{type: type} -> type
      _ -> :unknown
    end
  end
end
