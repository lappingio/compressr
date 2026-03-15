defmodule Compressr.Pipeline.Functions.Eval do
  @moduledoc """
  Eval function for adding, modifying, and removing fields on events.

  Configuration:
  - `fields` — a list of `{field_name, value_fn}` tuples where `value_fn`
    is a function that receives the event and returns the new field value
  - `remove_fields` — a list of field name patterns to remove (supports
    wildcards via regex matching with `*` converted to `.*`)
  - `keep_fields` — a list of field names to keep; when specified, only
    these fields (plus `_raw` and `_time`) are retained. Keep takes
    precedence over remove.
  """

  @behaviour Compressr.Pipeline.Function

  alias Compressr.Event

  @impl true
  def execute(event, config) when is_map(event) and is_map(config) do
    event =
      event
      |> apply_field_expressions(Map.get(config, :fields, []))
      |> apply_keep_or_remove(config)

    {:ok, event}
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp apply_field_expressions(event, fields) do
    Enum.reduce(fields, event, fn {field_name, value_fn}, acc ->
      value = if is_function(value_fn, 1), do: value_fn.(acc), else: value_fn
      Event.put_field(acc, field_name, value)
    end)
  end

  defp apply_keep_or_remove(event, config) do
    keep_fields = Map.get(config, :keep_fields, [])
    remove_fields = Map.get(config, :remove_fields, [])

    cond do
      keep_fields != [] ->
        # Keep only specified fields plus _raw and _time
        preserved = MapSet.new(["_raw", "_time"] ++ keep_fields)

        Map.filter(event, fn {key, _val} ->
          not is_binary(key) or MapSet.member?(preserved, key) or
            not Compressr.Event.Field.user_field?(key)
        end)

      remove_fields != [] ->
        Enum.reduce(remove_fields, event, fn pattern, acc ->
          remove_matching_fields(acc, pattern)
        end)

      true ->
        event
    end
  end

  defp remove_matching_fields(event, pattern) do
    if String.contains?(pattern, "*") do
      regex_pattern = pattern |> Regex.escape() |> String.replace("\\*", ".*")
      {:ok, regex} = Regex.compile("^#{regex_pattern}$")

      Map.reject(event, fn {key, _val} ->
        is_binary(key) and Compressr.Event.Field.user_field?(key) and
          key not in ["_raw", "_time"] and Regex.match?(regex, key)
      end)
    else
      Event.delete_field(event, pattern)
    end
  end
end
