defmodule Compressr.Schema.Registry.Classifier do
  @moduledoc """
  Log type classification engine.

  Classifies events into log types using structural fingerprinting as the
  primary method. Supports operator-defined classification rules including
  field presence rules and regex pattern matching on `_raw`.

  Classification priority (highest to lowest):
  1. Operator-defined rules (field presence, regex)
  2. Structural fingerprinting (hash of sorted user field names)
  """

  alias Compressr.Schema.Schema

  @type classification_rule ::
          {:field_presence, %{fields: [String.t()], log_type_id: String.t()}}
          | {:regex, %{pattern: Regex.t(), log_type_id: String.t()}}

  @doc """
  Classify a single event, returning a log_type_id.

  The log_type_id is derived from the structural fingerprint of the event's
  user fields (sorted field names hashed). Operator-defined rules can override
  the fingerprint-based classification.

  ## Options

    * `:rules` - list of classification rules to apply before fingerprinting

  ## Examples

      iex> classify(%{"host" => "server1", "level" => "info", "_time" => 123})
      "fp_" <> _hex_string

  """
  @spec classify(map(), keyword()) :: String.t()
  def classify(event, opts \\ []) when is_map(event) do
    rules = Keyword.get(opts, :rules, [])

    case apply_rules(event, rules) do
      {:ok, log_type_id} -> log_type_id
      :no_match -> fingerprint_classify(event)
    end
  end

  @doc """
  Classify a batch of events, returning a map of log_type_id => [events].

  ## Options

    * `:rules` - list of classification rules to apply before fingerprinting

  """
  @spec classify_batch([map()], keyword()) :: %{String.t() => [map()]}
  def classify_batch(events, opts \\ []) when is_list(events) do
    Enum.group_by(events, fn event -> classify(event, opts) end)
  end

  @doc """
  Compute the structural fingerprint ID for an event.

  Returns a hex-encoded string prefixed with "fp_" based on the SHA-256 hash
  of the event's sorted user field names.
  """
  @spec fingerprint_id(map()) :: String.t()
  def fingerprint_id(event) when is_map(event) do
    fields =
      event
      |> Schema.user_fields()
      |> Map.keys()
      |> Enum.sort()

    hash = :crypto.hash(:sha256, :erlang.term_to_binary(fields))
    "fp_" <> Base.encode16(hash, case: :lower)
  end

  @doc """
  Compute the raw fingerprint binary for an event's field set.
  """
  @spec fingerprint(map()) :: binary()
  def fingerprint(event) when is_map(event) do
    fields =
      event
      |> Schema.user_fields()
      |> Map.keys()
      |> Enum.sort()

    :crypto.hash(:sha256, :erlang.term_to_binary(fields))
  end

  # --- Private ---

  defp fingerprint_classify(event) do
    fingerprint_id(event)
  end

  defp apply_rules(_event, []), do: :no_match

  defp apply_rules(event, [rule | rest]) do
    case match_rule(event, rule) do
      {:ok, log_type_id} -> {:ok, log_type_id}
      :no_match -> apply_rules(event, rest)
    end
  end

  defp match_rule(event, {:field_presence, %{fields: required_fields, log_type_id: log_type_id}}) do
    user_fields = Schema.user_fields(event)
    field_keys = Map.keys(user_fields)

    if Enum.all?(required_fields, &(&1 in field_keys)) do
      {:ok, log_type_id}
    else
      :no_match
    end
  end

  defp match_rule(event, {:regex, %{pattern: pattern, log_type_id: log_type_id}}) do
    raw = Map.get(event, "_raw", "")

    if is_binary(raw) and Regex.match?(pattern, raw) do
      {:ok, log_type_id}
    else
      :no_match
    end
  end

  defp match_rule(_event, _unknown_rule), do: :no_match
end
