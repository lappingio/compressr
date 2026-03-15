defmodule Compressr.Pipeline.Functions.Rename do
  @moduledoc """
  Rename function for modifying field names on events.

  Renames fields using a map of old_name => new_name pairs.

  Configuration:
  - `renames` — a map of `%{"old_name" => "new_name"}` pairs
  - `rename_fn` — an optional function `fn event -> event` for dynamic renaming,
    applied after explicit renames
  """

  @behaviour Compressr.Pipeline.Function

  alias Compressr.Event

  @impl true
  def execute(event, config) when is_map(event) and is_map(config) do
    renames = Map.get(config, :renames, %{})
    rename_fn = Map.get(config, :rename_fn)

    event =
      Enum.reduce(renames, event, fn {old_name, new_name}, acc ->
        case Event.get_field(acc, old_name) do
          nil ->
            acc

          value ->
            acc
            |> Event.delete_field(old_name)
            |> Event.put_field(new_name, value)
        end
      end)

    event =
      if is_function(rename_fn, 1) do
        rename_fn.(event)
      else
        event
      end

    {:ok, event}
  rescue
    e -> {:error, Exception.message(e)}
  end
end
