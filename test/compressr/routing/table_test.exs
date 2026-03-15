defmodule Compressr.Routing.TableTest do
  use ExUnit.Case, async: true

  alias Compressr.Event
  alias Compressr.Routing.Table
  alias Compressr.Routing.Route
  alias Compressr.Routing.DefaultRoute
  alias Compressr.Routing.DevNull

  setup do
    {:ok, pid} = Table.start_link(name: :"table_#{:erlang.unique_integer([:positive])}")
    %{table: pid}
  end

  defp make_route(overrides \\ []) do
    defaults = [
      id: "route-#{:erlang.unique_integer([:positive])}",
      name: "route-#{:erlang.unique_integer([:positive])}",
      filter: fn _event -> true end,
      pipeline_id: "passthrough",
      destination_id: "test-dest",
      position: 1,
      final: true,
      enabled: true
    ]

    Route.new(Keyword.merge(defaults, overrides))
  end

  defp apache_event do
    Event.new(%{"source" => "apache", "_raw" => "apache log line"})
  end

  defp nginx_event do
    Event.new(%{"source" => "nginx", "_raw" => "nginx log line"})
  end

  # -------------------------------------------------------------------
  # Evaluation tests
  # -------------------------------------------------------------------

  describe "evaluate/2 — empty table" do
    test "falls through to default route", %{table: table} do
      event = apache_event()
      result = Table.evaluate(event, table)

      assert [{route, ^event}] = result
      assert DefaultRoute.default?(route)
    end
  end

  describe "evaluate/2 — single route" do
    test "matches event and returns it", %{table: table} do
      route = make_route(
        id: "r1",
        name: "apache-route",
        filter: fn e -> Map.get(e, "source") == "apache" end,
        position: 1
      )

      :ok = Table.add_route(route, table)

      event = apache_event()
      [{matched, _ev}] = Table.evaluate(event, table)

      assert matched.id == "r1"
    end

    test "non-matching event falls to default", %{table: table} do
      route = make_route(
        id: "r1",
        name: "apache-only",
        filter: fn e -> Map.get(e, "source") == "apache" end,
        position: 1
      )

      :ok = Table.add_route(route, table)

      event = nginx_event()
      [{matched, _ev}] = Table.evaluate(event, table)

      assert DefaultRoute.default?(matched)
    end
  end

  describe "evaluate/2 — Final flag" do
    test "final=true stops evaluation at first match", %{table: table} do
      r1 = make_route(
        id: "r1",
        name: "catch-all-final",
        filter: fn _e -> true end,
        position: 1,
        final: true,
        destination_id: "dest-1"
      )

      r2 = make_route(
        id: "r2",
        name: "never-reached",
        filter: fn _e -> true end,
        position: 2,
        destination_id: "dest-2"
      )

      :ok = Table.add_route(r1, table)
      :ok = Table.add_route(r2, table)

      result = Table.evaluate(apache_event(), table)
      assert length(result) == 1
      [{matched, _}] = result
      assert matched.id == "r1"
    end

    test "final=false clones event and continues evaluation", %{table: table} do
      r1 = make_route(
        id: "r1",
        name: "clone-route",
        filter: fn _e -> true end,
        position: 1,
        final: false,
        destination_id: "dest-1"
      )

      r2 = make_route(
        id: "r2",
        name: "second-route",
        filter: fn _e -> true end,
        position: 2,
        final: true,
        destination_id: "dest-2"
      )

      :ok = Table.add_route(r1, table)
      :ok = Table.add_route(r2, table)

      result = Table.evaluate(apache_event(), table)
      assert length(result) == 2

      [{m1, e1}, {m2, e2}] = result
      assert m1.id == "r1"
      assert m2.id == "r2"

      # Cloned events should have the same data but be distinct maps
      assert e1["source"] == "apache"
      assert e2["source"] == "apache"
    end

    test "multiple non-final routes clone to all plus default", %{table: table} do
      r1 = make_route(
        id: "r1",
        name: "first-nonfinal",
        filter: fn _e -> true end,
        position: 1,
        final: false
      )

      r2 = make_route(
        id: "r2",
        name: "second-nonfinal",
        filter: fn _e -> true end,
        position: 2,
        final: false
      )

      :ok = Table.add_route(r1, table)
      :ok = Table.add_route(r2, table)

      result = Table.evaluate(apache_event(), table)
      # r1 (clone) + r2 (clone) + default (original)
      assert length(result) == 3

      ids = Enum.map(result, fn {route, _} -> route.id end)
      assert "r1" in ids
      assert "r2" in ids
      assert DefaultRoute.id() in ids
    end
  end

  describe "evaluate/2 — disabled routes" do
    test "disabled routes are skipped", %{table: table} do
      r1 = make_route(
        id: "r1",
        name: "disabled-route",
        filter: fn _e -> true end,
        position: 1,
        enabled: false,
        destination_id: "dest-1"
      )

      r2 = make_route(
        id: "r2",
        name: "enabled-route",
        filter: fn _e -> true end,
        position: 2,
        enabled: true,
        destination_id: "dest-2"
      )

      :ok = Table.add_route(r1, table)
      :ok = Table.add_route(r2, table)

      [{matched, _}] = Table.evaluate(apache_event(), table)
      assert matched.id == "r2"
    end

    test "all routes disabled falls to default", %{table: table} do
      r1 = make_route(
        id: "r1",
        name: "disabled-1",
        filter: fn _e -> true end,
        position: 1,
        enabled: false
      )

      :ok = Table.add_route(r1, table)

      [{matched, _}] = Table.evaluate(apache_event(), table)
      assert DefaultRoute.default?(matched)
    end
  end

  describe "evaluate/2 — position ordering" do
    test "routes are evaluated in ascending position order", %{table: table} do
      # Add in reverse order to verify sorting
      r3 = make_route(
        id: "r3",
        name: "third",
        filter: fn e -> Map.get(e, "source") == "apache" end,
        position: 3,
        final: true
      )

      r1 = make_route(
        id: "r1",
        name: "first",
        filter: fn e -> Map.get(e, "source") == "apache" end,
        position: 1,
        final: true
      )

      r2 = make_route(
        id: "r2",
        name: "second",
        filter: fn e -> Map.get(e, "source") == "apache" end,
        position: 2,
        final: true
      )

      :ok = Table.add_route(r3, table)
      :ok = Table.add_route(r1, table)
      :ok = Table.add_route(r2, table)

      [{matched, _}] = Table.evaluate(apache_event(), table)
      # r1 has the lowest position, so it should match first
      assert matched.id == "r1"
    end
  end

  # -------------------------------------------------------------------
  # CRUD tests
  # -------------------------------------------------------------------

  describe "add_route/2" do
    test "adds a route successfully", %{table: table} do
      route = make_route(id: "r1", name: "test-route")
      assert :ok = Table.add_route(route, table)

      routes = Table.list_routes(table)
      ids = Enum.map(routes, & &1.id)
      assert "r1" in ids
    end

    test "rejects duplicate route names", %{table: table} do
      r1 = make_route(id: "r1", name: "same-name", position: 1)
      r2 = make_route(id: "r2", name: "same-name", position: 2)

      assert :ok = Table.add_route(r1, table)
      assert {:error, :duplicate_name} = Table.add_route(r2, table)
    end

    test "route names are case-sensitive (different cases are allowed)", %{table: table} do
      r1 = make_route(id: "r1", name: "WebLogs", position: 1)
      r2 = make_route(id: "r2", name: "weblogs", position: 2)

      assert :ok = Table.add_route(r1, table)
      assert :ok = Table.add_route(r2, table)
    end
  end

  describe "remove_route/2" do
    test "removes an existing route", %{table: table} do
      route = make_route(id: "r1", name: "to-remove")
      :ok = Table.add_route(route, table)

      assert :ok = Table.remove_route("r1", table)

      routes = Table.list_routes(table)
      ids = Enum.map(routes, & &1.id)
      refute "r1" in ids
    end

    test "returns error for non-existent route", %{table: table} do
      assert {:error, :not_found} = Table.remove_route("nonexistent", table)
    end
  end

  describe "update_route/2" do
    test "updates an existing route", %{table: table} do
      route = make_route(id: "r1", name: "original", position: 1, final: true)
      :ok = Table.add_route(route, table)

      updated = %{route | final: false, name: "updated"}
      assert :ok = Table.update_route(updated, table)

      routes = Table.list_routes(table)
      found = Enum.find(routes, &(&1.id == "r1"))
      assert found.final == false
      assert found.name == "updated"
    end

    test "returns error for non-existent route", %{table: table} do
      route = make_route(id: "nonexistent", name: "ghost")
      assert {:error, :not_found} = Table.update_route(route, table)
    end
  end

  describe "reorder/2" do
    test "reorders routes by ID list", %{table: table} do
      r1 = make_route(id: "r1", name: "first", position: 1)
      r2 = make_route(id: "r2", name: "second", position: 2)
      r3 = make_route(id: "r3", name: "third", position: 3)

      :ok = Table.add_route(r1, table)
      :ok = Table.add_route(r2, table)
      :ok = Table.add_route(r3, table)

      # Reverse the order
      :ok = Table.reorder(["r3", "r2", "r1"], table)

      routes = Table.list_routes(table)
      # Last one is always the default
      user_routes = Enum.reject(routes, &DefaultRoute.default?/1)
      sorted = Enum.sort_by(user_routes, & &1.position)

      assert Enum.map(sorted, & &1.id) == ["r3", "r2", "r1"]
    end

    test "default route cannot be reordered", %{table: table} do
      r1 = make_route(id: "r1", name: "first", position: 1)
      :ok = Table.add_route(r1, table)

      # Including default ID in reorder should be ignored
      :ok = Table.reorder([DefaultRoute.id(), "r1"], table)

      routes = Table.list_routes(table)
      default = List.last(routes)
      assert DefaultRoute.default?(default)
    end
  end

  describe "list_routes/1" do
    test "includes default route at the end", %{table: table} do
      routes = Table.list_routes(table)
      assert length(routes) == 1
      assert DefaultRoute.default?(hd(routes))
    end

    test "returns routes in position order with default last", %{table: table} do
      r2 = make_route(id: "r2", name: "second", position: 2)
      r1 = make_route(id: "r1", name: "first", position: 1)

      :ok = Table.add_route(r2, table)
      :ok = Table.add_route(r1, table)

      routes = Table.list_routes(table)
      assert length(routes) == 3

      [first, second, default] = routes
      assert first.id == "r1"
      assert second.id == "r2"
      assert DefaultRoute.default?(default)
    end
  end

  # -------------------------------------------------------------------
  # Default route and DevNull
  # -------------------------------------------------------------------

  describe "default route" do
    test "uses DevNull as default destination when not configured", %{table: table} do
      routes = Table.list_routes(table)
      default = Enum.find(routes, &DefaultRoute.default?/1)
      assert default.destination_id == DevNull.destination_id()
    end

    test "uses custom destination when configured" do
      {:ok, pid} =
        Table.start_link(
          name: :"custom_default_#{:erlang.unique_integer([:positive])}",
          default_destination_id: "my-s3-bucket"
        )

      routes = Table.list_routes(pid)
      default = Enum.find(routes, &DefaultRoute.default?/1)
      assert default.destination_id == "my-s3-bucket"
    end
  end

  describe "DevNull destination" do
    test "a route pointing to devnull matches and returns devnull destination", %{table: table} do
      route = make_route(
        id: "drop-debug",
        name: "drop-debug-events",
        filter: fn e -> Map.get(e, "level") == "debug" end,
        destination_id: DevNull.destination_id(),
        position: 1
      )

      :ok = Table.add_route(route, table)

      event = Event.new(%{"level" => "debug", "_raw" => "debug msg"})
      [{matched, _}] = Table.evaluate(event, table)

      assert matched.destination_id == "devnull"
    end
  end
end
