defmodule Compressr.Pipeline.Functions.RegexExtract do
  @moduledoc """
  Regex Extract function for extracting named capture groups from event fields.

  Uses regular expressions with named capture groups to extract values from a
  source field and add them as new fields on the event.

  Configuration:
  - `regex` — a compiled `Regex` with named capture groups, or a regex pattern string
  - `source_field` — the field to extract from (defaults to `"_raw"`)
  """

  @behaviour Compressr.Pipeline.Function

  alias Compressr.Event

  @impl true
  def execute(event, config) when is_map(event) and is_map(config) do
    source_field = Map.get(config, :source_field, "_raw")
    regex = ensure_regex(Map.fetch!(config, :regex))
    source_value = Event.get_field(event, source_field)

    event =
      if is_binary(source_value) do
        case Regex.named_captures(regex, source_value) do
          nil ->
            event

          captures ->
            Enum.reduce(captures, event, fn {name, value}, acc ->
              Event.put_field(acc, name, value)
            end)
        end
      else
        event
      end

    {:ok, event}
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp ensure_regex(%Regex{} = regex), do: regex

  defp ensure_regex(pattern) when is_binary(pattern) do
    {:ok, regex} = Regex.compile(pattern)
    regex
  end
end
