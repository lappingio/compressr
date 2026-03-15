defmodule Compressr.Pipeline.Functions.Mask do
  @moduledoc """
  Mask function for redacting sensitive data in event fields.

  Applies regex-based pattern replacement to specified fields on the event.

  Configuration:
  - `rules` — a list of masking rule maps, each containing:
    - `regex` — a compiled `Regex` or regex pattern string
    - `replacement` — the replacement string
    - `enabled` — boolean, defaults to true (individually toggleable)
  - `fields` — a list of field names to apply masking to (defaults to `["_raw"]`)
  """

  @behaviour Compressr.Pipeline.Function

  alias Compressr.Event

  @impl true
  def execute(event, config) when is_map(event) and is_map(config) do
    rules = Map.get(config, :rules, [])
    fields = Map.get(config, :fields, ["_raw"])

    enabled_rules =
      Enum.filter(rules, fn rule ->
        Map.get(rule, :enabled, true)
      end)

    event =
      Enum.reduce(fields, event, fn field, acc ->
        value = Event.get_field(acc, field)

        if is_binary(value) do
          masked = apply_rules(value, enabled_rules)
          Event.put_field(acc, field, masked)
        else
          acc
        end
      end)

    {:ok, event}
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp apply_rules(value, rules) do
    Enum.reduce(rules, value, fn rule, acc ->
      regex = ensure_regex(rule.regex)
      replacement = Map.get(rule, :replacement, "")
      Regex.replace(regex, acc, replacement)
    end)
  end

  defp ensure_regex(%Regex{} = regex), do: regex

  defp ensure_regex(pattern) when is_binary(pattern) do
    {:ok, regex} = Regex.compile(pattern)
    regex
  end
end
