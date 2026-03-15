defmodule Compressr.Routing.Table do
  @moduledoc """
  A GenServer holding the current route table — an ordered list of routes.

  Routes are evaluated in ascending position order. The table always includes
  a default catch-all route at the bottom that matches any event not caught
  by preceding routes.

  ## Evaluation semantics

  - Disabled routes are skipped entirely.
  - When a route's filter matches an event and `final` is true, evaluation
    stops and `[{route, event}]` is returned.
  - When a route's filter matches and `final` is false, the event is cloned
    for this route's destination and the original continues evaluation.
  - If no user-defined route matches, the default route catches the event.
  """

  use GenServer

  alias Compressr.Routing.DefaultRoute
  alias Compressr.Routing.Route

  # -------------------------------------------------------------------
  # Client API
  # -------------------------------------------------------------------

  @doc """
  Starts the route table GenServer.

  ## Options

  - `:name` — registered name (defaults to `__MODULE__`)
  - `:default_destination_id` — destination for the default catch-all route
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    default_dest = Keyword.get(opts, :default_destination_id, nil)

    default_route_opts =
      if default_dest, do: [destination_id: default_dest], else: []

    GenServer.start_link(__MODULE__, %{default_route_opts: default_route_opts}, name: name)
  end

  @doc """
  Evaluates an event against the route table in position order.

  Returns a list of `{%Route{}, event}` tuples representing matched routes
  and the events to be forwarded.
  """
  @spec evaluate(map(), GenServer.server()) :: [{Route.t(), map()}]
  def evaluate(event, server \\ __MODULE__) do
    GenServer.call(server, {:evaluate, event})
  end

  @doc """
  Adds a route to the table. Returns `:ok` or `{:error, reason}`.
  """
  @spec add_route(Route.t(), GenServer.server()) :: :ok | {:error, term()}
  def add_route(%Route{} = route, server \\ __MODULE__) do
    GenServer.call(server, {:add_route, route})
  end

  @doc """
  Removes a route by ID. Returns `:ok` or `{:error, :not_found}`.
  """
  @spec remove_route(String.t(), GenServer.server()) :: :ok | {:error, :not_found}
  def remove_route(route_id, server \\ __MODULE__) when is_binary(route_id) do
    GenServer.call(server, {:remove_route, route_id})
  end

  @doc """
  Updates an existing route (matched by ID). Returns `:ok` or `{:error, :not_found}`.
  """
  @spec update_route(Route.t(), GenServer.server()) :: :ok | {:error, :not_found}
  def update_route(%Route{} = route, server \\ __MODULE__) do
    GenServer.call(server, {:update_route, route})
  end

  @doc """
  Replaces the position values for routes according to the given ordered list
  of route IDs. IDs not present in the table are ignored. The default route
  always remains last.

  Returns `:ok`.
  """
  @spec reorder([String.t()], GenServer.server()) :: :ok
  def reorder(ordered_ids, server \\ __MODULE__) when is_list(ordered_ids) do
    GenServer.call(server, {:reorder, ordered_ids})
  end

  @doc """
  Lists all routes (including the default) in position order.
  """
  @spec list_routes(GenServer.server()) :: [Route.t()]
  def list_routes(server \\ __MODULE__) do
    GenServer.call(server, :list_routes)
  end

  # -------------------------------------------------------------------
  # GenServer callbacks
  # -------------------------------------------------------------------

  @impl true
  def init(%{default_route_opts: default_route_opts}) do
    default_route = DefaultRoute.build(default_route_opts)
    {:ok, %{routes: [], default_route: default_route}}
  end

  @impl true
  def handle_call({:evaluate, event}, _from, state) do
    result = do_evaluate(event, sorted_routes(state), state.default_route)
    {:reply, result, state}
  end

  def handle_call({:add_route, route}, _from, state) do
    if DefaultRoute.default?(route) do
      {:reply, {:error, :cannot_add_default_route}, state}
    else
      if Enum.any?(state.routes, &(&1.name == route.name)) do
        {:reply, {:error, :duplicate_name}, state}
      else
        {:reply, :ok, %{state | routes: [route | state.routes]}}
      end
    end
  end

  def handle_call({:remove_route, route_id}, _from, state) do
    case Enum.split_with(state.routes, &(&1.id == route_id)) do
      {[], _rest} ->
        {:reply, {:error, :not_found}, state}

      {_removed, rest} ->
        {:reply, :ok, %{state | routes: rest}}
    end
  end

  def handle_call({:update_route, route}, _from, state) do
    case Enum.find_index(state.routes, &(&1.id == route.id)) do
      nil ->
        {:reply, {:error, :not_found}, state}

      idx ->
        updated = List.replace_at(state.routes, idx, route)
        {:reply, :ok, %{state | routes: updated}}
    end
  end

  def handle_call({:reorder, ordered_ids}, _from, state) do
    # Filter out the default route ID from the ordering request
    ordered_ids = Enum.reject(ordered_ids, &(&1 == DefaultRoute.id()))

    route_map = Map.new(state.routes, &{&1.id, &1})

    reordered =
      ordered_ids
      |> Enum.with_index(1)
      |> Enum.reduce(route_map, fn {id, pos}, acc ->
        case Map.get(acc, id) do
          nil -> acc
          route -> Map.put(acc, id, %{route | position: pos})
        end
      end)
      |> Map.values()

    {:reply, :ok, %{state | routes: reordered}}
  end

  def handle_call(:list_routes, _from, state) do
    routes = sorted_routes(state) ++ [state.default_route]
    {:reply, routes, state}
  end

  # -------------------------------------------------------------------
  # Private helpers
  # -------------------------------------------------------------------

  defp sorted_routes(state) do
    Enum.sort_by(state.routes, & &1.position)
  end

  defp do_evaluate(event, [], default_route) do
    [{default_route, event}]
  end

  defp do_evaluate(event, [route | rest], default_route) do
    cond do
      not route.enabled ->
        do_evaluate(event, rest, default_route)

      Route.matches?(route, event) and route.final ->
        [{route, event}]

      Route.matches?(route, event) ->
        # Non-final: clone event for this route, original continues
        cloned_event = deep_copy(event)
        [{route, cloned_event} | do_evaluate(event, rest, default_route)]

      true ->
        do_evaluate(event, rest, default_route)
    end
  end

  defp deep_copy(event) do
    :erlang.binary_to_term(:erlang.term_to_binary(event))
  end
end
