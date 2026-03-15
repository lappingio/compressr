defmodule Compressr.Event do
  @moduledoc """
  Core Event module for Compressr.

  Events are represented as plain Elixir maps with at minimum two standard fields:
  - `_raw` — the original raw data as a string
  - `_time` — a Unix epoch timestamp (integer)

  Field categories:
  - Internal fields (`__` prefix): pipeline processing metadata, stripped on external serialization
  - System fields (`compressr_` prefix): added during post-processing, read-only in pipelines
  - User fields: everything else, freely readable and writable
  """

  alias Compressr.Event.Field

  @doc """
  Creates a new event from a map of fields.

  If `_time` is not provided, it defaults to the current Unix epoch timestamp.
  If `_raw` is not provided, it defaults to an empty string.
  """
  @spec new(map()) :: map()
  def new(fields \\ %{}) when is_map(fields) do
    fields
    |> ensure_raw()
    |> ensure_time()
  end

  @doc """
  Creates a new event from a raw string with optional overrides.

  The raw string is stored in `_raw`. Options may include `_time` or any
  other fields to set on the event.
  """
  @spec new(String.t(), keyword() | map()) :: map()
  def new(raw, opts) when is_binary(raw) do
    extra =
      case opts do
        opts when is_list(opts) -> Map.new(opts, fn {k, v} -> {to_string(k), v} end)
        opts when is_map(opts) -> opts
      end

    extra
    |> Map.put("_raw", raw)
    |> ensure_time()
  end

  @doc """
  Creates an event from a JSON string.

  Parses the JSON and merges the resulting fields into the event,
  preserving the original JSON string as `_raw`.

  Returns `{:ok, event}` on success or `{:error, reason}` on failure.
  """
  @spec from_json(String.t()) :: {:ok, map()} | {:error, term()}
  def from_json(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, parsed} when is_map(parsed) ->
        event =
          parsed
          |> Map.put("_raw", json)
          |> ensure_time()

        {:ok, event}

      {:ok, _not_a_map} ->
        {:error, :not_a_json_object}

      {:error, %Jason.DecodeError{} = error} ->
        {:error, error}
    end
  end

  @doc """
  Creates an event from a raw string.

  Sets `_raw` to the provided string and `_time` to the current Unix epoch.
  """
  @spec from_raw(String.t()) :: map()
  def from_raw(raw) when is_binary(raw) do
    %{"_raw" => raw, "_time" => current_time()}
  end

  @doc """
  Sets a field on the event.

  Internal fields (`__` prefix) cannot be set through this function — the
  event is returned unchanged. Use `put_internal/3` for internal fields.

  System fields (`compressr_` prefix) cannot be set through this function —
  the event is returned unchanged. Use `put_system/3` for system fields.
  """
  @spec put_field(map(), String.t(), term()) :: map()
  def put_field(event, name, value) when is_map(event) and is_binary(name) do
    cond do
      Field.internal_field?(name) -> event
      Field.system_field?(name) -> event
      true -> Map.put(event, name, value)
    end
  end

  @doc """
  Gets a field value from the event. Returns `nil` if the field does not exist.
  """
  @spec get_field(map(), String.t()) :: term()
  def get_field(event, name) when is_map(event) and is_binary(name) do
    Map.get(event, name)
  end

  @doc """
  Deletes a field from the event.

  Internal fields (`__` prefix) and system fields (`compressr_` prefix)
  cannot be deleted through this function — the event is returned unchanged.
  """
  @spec delete_field(map(), String.t()) :: map()
  def delete_field(event, name) when is_map(event) and is_binary(name) do
    cond do
      Field.internal_field?(name) -> event
      Field.system_field?(name) -> event
      true -> Map.delete(event, name)
    end
  end

  @doc """
  Sets an internal field (`__` prefixed) on the event.

  This is intended for use by sources and pipeline internals only.
  """
  @spec put_internal(map(), String.t(), term()) :: map()
  def put_internal(event, "__" <> _ = name, value) when is_map(event) do
    Map.put(event, name, value)
  end

  @doc """
  Sets a system field (`compressr_` prefixed) on the event.

  This is intended for use by post-processing only.
  """
  @spec put_system(map(), String.t(), term()) :: map()
  def put_system(event, "compressr_" <> _ = name, value) when is_map(event) do
    Map.put(event, name, value)
  end

  @doc """
  Converts an event to an external map by stripping all internal fields
  (`__` prefix). System fields and user fields are preserved.
  """
  @spec to_external_map(map()) :: map()
  def to_external_map(event) when is_map(event) do
    Field.strip_internal_fields(event)
  end

  @doc """
  Serializes the event to a JSON string, stripping internal fields.

  Returns `{:ok, json}` or `{:error, reason}`.
  """
  @spec to_json(map()) :: {:ok, String.t()} | {:error, term()}
  def to_json(event) when is_map(event) do
    event
    |> to_external_map()
    |> Jason.encode()
  end

  # --- Private helpers ---

  defp ensure_raw(map) do
    Map.put_new(map, "_raw", "")
  end

  defp ensure_time(map) do
    Map.put_new(map, "_time", current_time())
  end

  defp current_time do
    System.os_time(:second)
  end
end
