defmodule Compressr.Routing.DefaultRoute do
  @moduledoc """
  The default catch-all route that sits at the bottom of every route table.

  This route always matches (filter returns true), has Final set to ON,
  and routes unmatched events to a configurable default destination.
  Its position is always last and it cannot be reordered above other routes.
  """

  alias Compressr.Routing.DevNull
  alias Compressr.Routing.Route

  @default_id "__default__"
  @default_name "Default"
  @default_position 999_999_999

  @doc """
  Returns the well-known default route ID.
  """
  @spec id() :: String.t()
  def id, do: @default_id

  @doc """
  Builds the default catch-all route.

  ## Options

  - `:destination_id` — the destination to route unmatched events to
    (defaults to DevNull)
  """
  @spec build(keyword()) :: Route.t()
  def build(opts \\ []) do
    destination_id = Keyword.get(opts, :destination_id, DevNull.destination_id())

    %Route{
      id: @default_id,
      name: @default_name,
      filter: fn _event -> true end,
      pipeline_id: "passthrough",
      destination_id: destination_id,
      final: true,
      enabled: true,
      position: @default_position,
      description: "Default catch-all route for unmatched events"
    }
  end

  @doc """
  Returns true if the given route is the default catch-all route.
  """
  @spec default?(Route.t()) :: boolean()
  def default?(%Route{id: id}), do: id == @default_id
end
