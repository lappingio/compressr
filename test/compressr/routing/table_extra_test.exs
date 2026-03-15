defmodule Compressr.Routing.TableExtraTest do
  use ExUnit.Case, async: true

  alias Compressr.Routing.Table
  alias Compressr.Routing.Route
  alias Compressr.Routing.DefaultRoute

  setup do
    {:ok, pid} = Table.start_link(name: :"table_extra_#{:erlang.unique_integer([:positive])}")
    %{table: pid}
  end

  describe "add_route/2 edge cases" do
    test "cannot add the default route", %{table: table} do
      default = DefaultRoute.build()
      assert {:error, :cannot_add_default_route} = Table.add_route(default, table)
    end
  end

  describe "evaluate/2 — filter that returns false for some events" do
    test "non-matching filter on non-final route skips to next", %{table: table} do
      r1 = Route.new(
        id: "skip-1",
        name: "no-match",
        filter: fn _e -> false end,
        pipeline_id: "p",
        destination_id: "d",
        position: 1,
        final: false
      )

      r2 = Route.new(
        id: "catch-2",
        name: "catch",
        filter: fn _e -> true end,
        pipeline_id: "p",
        destination_id: "d2",
        position: 2,
        final: true
      )

      :ok = Table.add_route(r1, table)
      :ok = Table.add_route(r2, table)

      event = %{"_raw" => "test", "_time" => 123}
      [{matched, _}] = Table.evaluate(event, table)
      assert matched.id == "catch-2"
    end
  end

  describe "reorder/2 edge cases" do
    test "reorder with unknown IDs ignores them", %{table: table} do
      r1 = Route.new(
        id: "known",
        name: "known-route",
        filter: fn _e -> true end,
        pipeline_id: "p",
        destination_id: "d",
        position: 1
      )

      :ok = Table.add_route(r1, table)
      assert :ok = Table.reorder(["unknown-id", "known"], table)

      routes = Table.list_routes(table)
      user_routes = Enum.reject(routes, &DefaultRoute.default?/1)
      assert length(user_routes) == 1
    end
  end
end
