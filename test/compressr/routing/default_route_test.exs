defmodule Compressr.Routing.DefaultRouteTest do
  use ExUnit.Case, async: true

  alias Compressr.Routing.DefaultRoute
  alias Compressr.Routing.Route
  alias Compressr.Routing.DevNull

  describe "id/0" do
    test "returns the well-known default route ID" do
      assert DefaultRoute.id() == "__default__"
    end
  end

  describe "build/0" do
    test "builds a default route with DevNull destination" do
      route = DefaultRoute.build()

      assert %Route{} = route
      assert route.id == "__default__"
      assert route.name == "Default"
      assert route.pipeline_id == "passthrough"
      assert route.destination_id == DevNull.destination_id()
      assert route.final == true
      assert route.enabled == true
      assert route.position == 999_999_999
      assert route.description == "Default catch-all route for unmatched events"
    end

    test "filter always returns true" do
      route = DefaultRoute.build()
      assert route.filter.(%{"any" => "event"})
      assert route.filter.(%{})
    end
  end

  describe "build/1" do
    test "accepts custom destination_id" do
      route = DefaultRoute.build(destination_id: "my-custom-dest")
      assert route.destination_id == "my-custom-dest"
    end

    test "uses DevNull when no destination_id provided" do
      route = DefaultRoute.build([])
      assert route.destination_id == DevNull.destination_id()
    end
  end

  describe "default?/1" do
    test "returns true for the default route" do
      route = DefaultRoute.build()
      assert DefaultRoute.default?(route) == true
    end

    test "returns false for a non-default route" do
      route = Route.new(
        id: "not-default",
        name: "test",
        filter: fn _e -> true end,
        pipeline_id: "p",
        destination_id: "d",
        position: 1
      )

      assert DefaultRoute.default?(route) == false
    end

    test "returns true when id matches default id" do
      route = %Route{
        id: "__default__",
        name: "fake",
        filter: fn _e -> false end,
        pipeline_id: "p",
        destination_id: "d",
        position: 0
      }

      assert DefaultRoute.default?(route) == true
    end
  end
end
