defmodule Compressr.Event.Field do
  @moduledoc """
  Field classification helpers for Compressr events.

  Fields are classified into three categories:
  - Internal fields: prefixed with `__`, used for pipeline processing metadata
  - System fields: prefixed with `compressr_`, added during post-processing
  - User fields: everything else, including standard fields like `_raw` and `_time`
  """

  @doc """
  Returns true if the field name is an internal field (prefixed with `__`).
  """
  @spec internal_field?(String.t()) :: boolean()
  def internal_field?("__" <> _), do: true
  def internal_field?(_), do: false

  @doc """
  Returns true if the field name is a system field (prefixed with `compressr_`).
  """
  @spec system_field?(String.t()) :: boolean()
  def system_field?("compressr_" <> _), do: true
  def system_field?(_), do: false

  @doc """
  Returns true if the field name is a user field (not internal and not system).
  """
  @spec user_field?(String.t()) :: boolean()
  def user_field?(name) when is_binary(name) do
    not internal_field?(name) and not system_field?(name)
  end

  @doc """
  Strips all internal fields (`__` prefixed) from a map.
  """
  @spec strip_internal_fields(map()) :: map()
  def strip_internal_fields(map) when is_map(map) do
    Map.reject(map, fn {key, _value} ->
      is_binary(key) and internal_field?(key)
    end)
  end

  @doc """
  Strips all system fields (`compressr_` prefixed) from a map.
  """
  @spec strip_system_fields(map()) :: map()
  def strip_system_fields(map) when is_map(map) do
    Map.reject(map, fn {key, _value} ->
      is_binary(key) and system_field?(key)
    end)
  end
end
