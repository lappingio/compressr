defmodule Compressr.RoutingTest do
  use ExUnit.Case, async: true

  alias Compressr.Routing
  alias Compressr.Routing.{Table, Route, DefaultRoute, DevNull}
  alias Compressr.Event

  setup do
    {:ok, pid} = Table.start_link(name: :"routing_test_#{:erlang.unique_integer([:positive])}")
    %{table: pid}
  end

  describe "evaluate/2 delegation" do
    test "delegates to Table.evaluate", %{table: table} do
      event = Event.new(%{"source" => "test"})
      result = Routing.evaluate(event, table)
      assert [{route, _ev}] = result
      assert DefaultRoute.default?(route)
    end
  end

  describe "add_route/2 delegation" do
    test "delegates to Table.add_route", %{table: table} do
      route = Route.new(
        id: "del-r1",
        name: "delegation-test",
        filter: fn _e -> true end,
        pipeline_id: "passthrough",
        destination_id: "test-dest",
        position: 1
      )

      assert :ok = Routing.add_route(route, table)
      routes = Routing.list_routes(table)
      ids = Enum.map(routes, & &1.id)
      assert "del-r1" in ids
    end
  end

  describe "remove_route/2 delegation" do
    test "delegates to Table.remove_route", %{table: table} do
      route = Route.new(
        id: "del-r2",
        name: "remove-test",
        filter: fn _e -> true end,
        pipeline_id: "passthrough",
        destination_id: "test-dest",
        position: 1
      )

      :ok = Routing.add_route(route, table)
      assert :ok = Routing.remove_route("del-r2", table)
    end

    test "returns error for non-existent route", %{table: table} do
      assert {:error, :not_found} = Routing.remove_route("nonexistent", table)
    end
  end

  describe "update_route/2 delegation" do
    test "delegates to Table.update_route", %{table: table} do
      route = Route.new(
        id: "del-r3",
        name: "update-test",
        filter: fn _e -> true end,
        pipeline_id: "passthrough",
        destination_id: "test-dest",
        position: 1,
        final: true
      )

      :ok = Routing.add_route(route, table)
      updated = %{route | final: false, name: "updated-test"}
      assert :ok = Routing.update_route(updated, table)
    end
  end

  describe "reorder/2 delegation" do
    test "delegates to Table.reorder", %{table: table} do
      r1 = Route.new(id: "ro-1", name: "first", filter: fn _e -> true end, pipeline_id: "p", destination_id: "d", position: 1)
      r2 = Route.new(id: "ro-2", name: "second", filter: fn _e -> true end, pipeline_id: "p", destination_id: "d", position: 2)

      :ok = Routing.add_route(r1, table)
      :ok = Routing.add_route(r2, table)

      assert :ok = Routing.reorder(["ro-2", "ro-1"], table)
    end
  end

  describe "list_routes/1 delegation" do
    test "delegates to Table.list_routes", %{table: table} do
      routes = Routing.list_routes(table)
      assert is_list(routes)
      assert length(routes) >= 1
    end
  end

  describe "devnull_destination_id/0" do
    test "returns the DevNull destination ID" do
      assert Routing.devnull_destination_id() == DevNull.destination_id()
      assert Routing.devnull_destination_id() == "devnull"
    end
  end

  describe "default_route_id/0" do
    test "returns the default route ID" do
      assert Routing.default_route_id() == DefaultRoute.id()
      assert Routing.default_route_id() == "__default__"
    end
  end

  describe "new_route/1" do
    test "creates a new Route struct" do
      route = Routing.new_route(
        id: "nr-1",
        name: "new-route",
        filter: fn _e -> true end,
        pipeline_id: "p1",
        destination_id: "d1",
        position: 1
      )

      assert %Route{} = route
      assert route.id == "nr-1"
      assert route.name == "new-route"
      assert route.pipeline_id == "p1"
      assert route.destination_id == "d1"
    end
  end
end
