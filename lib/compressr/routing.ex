defmodule Compressr.Routing do
  @moduledoc """
  The Routing context for Compressr.

  Provides a public API for managing routes and evaluating events against
  the route table. Routes define how incoming events are matched, processed
  through pipelines, and delivered to destinations.

  ## Overview

  - Routes are evaluated sequentially in ascending position order.
  - Each route has a filter function, a pipeline reference, and a destination reference.
  - The "Final" flag controls whether matching stops (final=true) or the event
    is cloned and evaluation continues (final=false).
  - A default catch-all route always exists at the bottom of the table.
  - The DevNull destination discards events silently.
  """

  alias Compressr.Routing.Table
  alias Compressr.Routing.Route
  alias Compressr.Routing.DefaultRoute
  alias Compressr.Routing.DevNull

  defdelegate evaluate(event, server \\ Table), to: Table
  defdelegate add_route(route, server \\ Table), to: Table
  defdelegate remove_route(route_id, server \\ Table), to: Table
  defdelegate update_route(route, server \\ Table), to: Table
  defdelegate reorder(ordered_ids, server \\ Table), to: Table
  defdelegate list_routes(server \\ Table), to: Table

  @doc """
  Returns the DevNull destination ID.
  """
  @spec devnull_destination_id() :: String.t()
  def devnull_destination_id, do: DevNull.destination_id()

  @doc """
  Returns the default route ID.
  """
  @spec default_route_id() :: String.t()
  def default_route_id, do: DefaultRoute.id()

  @doc """
  Convenience: creates a new Route struct from keyword options.
  """
  @spec new_route(keyword()) :: Route.t()
  def new_route(attrs), do: Route.new(attrs)
end
