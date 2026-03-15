defmodule Compressr.Schema.Schema do
  @moduledoc """
  Schema representation for learned event schemas.

  A schema is a map of field_name => field_info, where field_info contains
  the inferred type, sample values, and first-seen timestamp.
  """

  @type field_info :: %{
          type: atom(),
          sample_values: list(),
          first_seen: DateTime.t()
        }

  @type t :: %{String.t() => field_info()}

  @max_sample_values 5

  @doc """
  Creates a new empty schema.
  """
  @spec new() :: t()
  def new, do: %{}

  @doc """
  Infer the Elixir type from a value.

  Returns one of: :string, :integer, :float, :boolean, :map, :list, :nil
  """
  @spec infer_type(term()) :: atom()
  def infer_type(nil), do: :nil
  def infer_type(v) when is_binary(v), do: :string
  def infer_type(v) when is_integer(v), do: :integer
  def infer_type(v) when is_float(v), do: :float
  def infer_type(v) when is_boolean(v), do: :boolean
  def infer_type(v) when is_map(v), do: :map
  def infer_type(v) when is_list(v), do: :list
  def infer_type(_), do: :unknown

  @doc """
  Merge a new event's fields into an existing schema.

  For each field in the event:
  - If the field is new, add it with inferred type and current timestamp
  - If the field exists, update sample_values (up to max)
  - If the field's type differs from the existing type, keep the existing type
    (type changes are detected separately by the drift detector)

  Internal fields (prefixed with `_`) are excluded from schema learning.
  """
  @spec merge(t(), map()) :: t()
  def merge(schema, event) when is_map(schema) and is_map(event) do
    now = DateTime.utc_now()

    event
    |> user_fields()
    |> Enum.reduce(schema, fn {field_name, value}, acc ->
      case Map.get(acc, field_name) do
        nil ->
          Map.put(acc, field_name, %{
            type: infer_type(value),
            sample_values: [value],
            first_seen: now
          })

        existing ->
          updated_samples =
            if length(existing.sample_values) < @max_sample_values do
              existing.sample_values ++ [value]
            else
              existing.sample_values
            end

          Map.put(acc, field_name, %{existing | sample_values: updated_samples})
      end
    end)
  end

  @doc """
  Compute a structural fingerprint (hash) of an event's shape.

  The fingerprint is based on the sorted field names and inferred types
  of user fields. This provides a fast-path comparison: if the fingerprint
  matches, the event has the same structure and types as the baseline.
  """
  @spec fingerprint(map()) :: binary()
  def fingerprint(event_or_schema) when is_map(event_or_schema) do
    shape =
      event_or_schema
      |> user_fields()
      |> Enum.map(fn {k, v} -> {k, infer_type(v)} end)
      |> Enum.sort()

    :crypto.hash(:sha256, :erlang.term_to_binary(shape))
  end

  @doc """
  Compute a fingerprint from a schema (using its field names and types).
  """
  @spec schema_fingerprint(t()) :: binary()
  def schema_fingerprint(schema) when is_map(schema) do
    shape =
      schema
      |> Enum.map(fn {k, info} -> {k, info.type} end)
      |> Enum.sort()

    :crypto.hash(:sha256, :erlang.term_to_binary(shape))
  end

  @doc """
  Compare an event against a baseline schema and return a list of drifts.

  Returns a list of `{drift_type, field_name, details}` tuples.
  """
  @spec compare(t(), map()) :: [
          {:new_field, String.t(), term()}
          | {:missing_field, String.t(), nil}
          | {:type_change, String.t(), {atom(), atom()}}
        ]
  def compare(schema, event) when is_map(schema) and is_map(event) do
    event_fields = user_fields(event)
    schema_keys = MapSet.new(Map.keys(schema))
    event_keys = MapSet.new(Map.keys(event_fields))

    new_fields =
      event_keys
      |> MapSet.difference(schema_keys)
      |> Enum.map(fn field -> {:new_field, field, Map.get(event_fields, field)} end)

    missing_fields =
      schema_keys
      |> MapSet.difference(event_keys)
      |> Enum.map(fn field -> {:missing_field, field, nil} end)

    type_changes =
      schema_keys
      |> MapSet.intersection(event_keys)
      |> Enum.flat_map(fn field ->
        old_type = schema[field].type
        new_type = infer_type(Map.get(event_fields, field))

        if old_type != new_type and new_type != :nil do
          [{:type_change, field, {old_type, new_type}}]
        else
          []
        end
      end)

    new_fields ++ missing_fields ++ type_changes
  end

  @doc """
  Filter event fields to only include user fields (exclude internal/system fields).
  """
  @spec user_fields(map()) :: map()
  def user_fields(event) when is_map(event) do
    event
    |> Enum.reject(fn {k, _v} ->
      String.starts_with?(k, "_") or String.starts_with?(k, "compressr_")
    end)
    |> Map.new()
  end
end
