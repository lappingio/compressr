defmodule Compressr.Expression.Functions do
  @moduledoc """
  Built-in functions for the expression language.

  These are purpose-built for observability data manipulation:
  field existence checks, string operations, type coercion, and time.
  """

  @doc "Returns true if the field exists in the event and is not nil."
  @spec exists(map(), list(String.t())) :: boolean()
  def exists(event, field_path) when is_map(event) and is_list(field_path) do
    case get_nested(event, field_path) do
      :field_missing -> false
      nil -> false
      _ -> true
    end
  end

  @doc "Returns the length of a string, list, or map."
  @spec length(any()) :: non_neg_integer()
  def length(value) when is_binary(value), do: String.length(value)
  def length(value) when is_list(value), do: Kernel.length(value)
  def length(value) when is_map(value), do: map_size(value)
  def length(nil), do: 0

  @doc "Converts a string to lowercase."
  @spec downcase(any()) :: String.t()
  def downcase(value) when is_binary(value), do: String.downcase(value)
  def downcase(nil), do: nil

  @doc "Converts a string to uppercase."
  @spec upcase(any()) :: String.t()
  def upcase(value) when is_binary(value), do: String.upcase(value)
  def upcase(nil), do: nil

  @doc "Converts a value to an integer."
  @spec to_int(any()) :: integer() | nil
  def to_int(value) when is_integer(value), do: value
  def to_int(value) when is_float(value), do: trunc(value)

  def to_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      {int, _rest} -> int
      :error -> nil
    end
  end

  def to_int(true), do: 1
  def to_int(false), do: 0
  def to_int(nil), do: nil

  @doc "Converts a value to a float."
  @spec to_float(any()) :: float() | nil
  def to_float(value) when is_float(value), do: value
  def to_float(value) when is_integer(value), do: value / 1

  def to_float(value) when is_binary(value) do
    case Float.parse(value) do
      {float, ""} -> float
      {float, _rest} -> float
      :error -> nil
    end
  end

  def to_float(nil), do: nil

  @doc "Converts a value to a string."
  @spec to_string(any()) :: String.t()
  def to_string(value) when is_binary(value), do: value
  def to_string(value) when is_integer(value), do: Integer.to_string(value)
  def to_string(value) when is_float(value), do: Float.to_string(value)
  def to_string(true), do: "true"
  def to_string(false), do: "false"
  def to_string(nil), do: ""
  def to_string(value) when is_atom(value), do: Atom.to_string(value)
  def to_string(value), do: inspect(value)

  @doc "Returns the current Unix timestamp as an integer."
  @spec now() :: integer()
  def now, do: System.system_time(:second)

  @doc "Returns true if the string contains the substring."
  @spec contains(String.t() | nil, String.t()) :: boolean()
  def contains(nil, _substring), do: false

  def contains(string, substring) when is_binary(string) and is_binary(substring) do
    String.contains?(string, substring)
  end

  @doc "Returns true if the string starts with the prefix."
  @spec starts_with(String.t() | nil, String.t()) :: boolean()
  def starts_with(nil, _prefix), do: false

  def starts_with(string, prefix) when is_binary(string) and is_binary(prefix) do
    String.starts_with?(string, prefix)
  end

  @doc "Returns true if the string ends with the suffix."
  @spec ends_with(String.t() | nil, String.t()) :: boolean()
  def ends_with(nil, _suffix), do: false

  def ends_with(string, suffix) when is_binary(string) and is_binary(suffix) do
    String.ends_with?(string, suffix)
  end

  @doc "Returns true if the string matches the regex pattern."
  @spec match(String.t() | nil, String.t()) :: boolean()
  def match(nil, _pattern), do: false

  def match(string, pattern) when is_binary(string) and is_binary(pattern) do
    case Regex.compile(pattern) do
      {:ok, regex} -> Regex.match?(regex, string)
      {:error, _} -> false
    end
  end

  @doc false
  def get_nested(map, []) when is_map(map), do: map
  def get_nested(value, []) when not is_map(value), do: value

  def get_nested(map, [key | rest]) when is_map(map) do
    case Map.fetch(map, key) do
      {:ok, value} -> get_nested(value, rest)
      :error -> :field_missing
    end
  end

  def get_nested(_non_map, [_ | _]), do: :field_missing
end
