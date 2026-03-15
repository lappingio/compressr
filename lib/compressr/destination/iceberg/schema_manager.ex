defmodule Compressr.Destination.Iceberg.SchemaManager do
  @moduledoc """
  Schema management for Iceberg tables.

  Provides schema inference from event data and schema evolution
  (detecting new fields). Schemas are represented as lists of field
  descriptors compatible with Iceberg's type system.

  ## Schema representation

  Each field is a map:

      %{name: "host", type: :string, nullable: true}

  Supported types: `:string`, `:integer`, `:long`, `:float`, `:double`,
  `:boolean`, `:timestamp`.

  Internal fields (`__` prefix) and the `_raw` field are excluded from
  the inferred schema since they are pipeline metadata.
  """

  @internal_prefix "__"
  @excluded_fields ["_raw"]

  @type field :: %{name: String.t(), type: atom(), nullable: boolean()}

  @doc """
  Infer an Iceberg-compatible schema from a list of events.

  Scans all events and builds a union of all fields found, inferring
  the type from the first non-nil value seen for each field.
  """
  @spec infer_schema([map()]) :: [field()]
  def infer_schema(events) when is_list(events) do
    events
    |> Enum.reduce(%{}, fn event, acc ->
      event
      |> Enum.reject(fn {k, _v} -> excluded?(k) end)
      |> Enum.reduce(acc, fn {key, value}, field_map ->
        Map.put_new(field_map, key, infer_type(value))
      end)
    end)
    |> Enum.map(fn {name, type} ->
      %{name: name, type: type, nullable: true}
    end)
    |> Enum.sort_by(& &1.name)
  end

  @doc """
  Evolve a schema by merging new fields discovered in `new_events`.

  Returns `{:ok, updated_schema, new_fields}` where `new_fields` is the
  list of fields that were added (empty list if no evolution occurred).
  """
  @spec evolve_schema([field()], [map()]) :: {:ok, [field()], [field()]}
  def evolve_schema(current_schema, new_events) do
    existing_names = MapSet.new(current_schema, & &1.name)
    inferred = infer_schema(new_events)

    new_fields =
      Enum.reject(inferred, fn field ->
        MapSet.member?(existing_names, field.name)
      end)

    updated_schema =
      (current_schema ++ new_fields)
      |> Enum.sort_by(& &1.name)

    {:ok, updated_schema, new_fields}
  end

  @doc """
  Infer the Iceberg type for an Elixir value.
  """
  @spec infer_type(term()) :: atom()
  def infer_type(value) when is_boolean(value), do: :boolean
  def infer_type(value) when is_integer(value) and value >= -2_147_483_648 and value <= 2_147_483_647, do: :integer
  def infer_type(value) when is_integer(value), do: :long
  def infer_type(value) when is_float(value), do: :double
  def infer_type(nil), do: :string
  def infer_type(value) when is_binary(value) do
    # Check if it looks like an ISO 8601 timestamp
    case DateTime.from_iso8601(value) do
      {:ok, _, _} -> :timestamp
      _ -> :string
    end
  end
  def infer_type(_), do: :string

  # --- Private ---

  defp excluded?(key) do
    String.starts_with?(key, @internal_prefix) or key in @excluded_fields
  end
end
