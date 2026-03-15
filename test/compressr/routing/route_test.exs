defmodule Compressr.Routing.RouteTest do
  use ExUnit.Case, async: true

  alias Compressr.Routing.Route

  defp valid_attrs(overrides \\ []) do
    Keyword.merge(
      [
        id: "route-1",
        name: "web-logs",
        filter: fn _event -> true end,
        pipeline_id: "extract-fields",
        destination_id: "s3-archive",
        position: 1
      ],
      overrides
    )
  end

  describe "new/1" do
    test "creates a route with all required fields" do
      route = Route.new(valid_attrs())

      assert route.id == "route-1"
      assert route.name == "web-logs"
      assert route.pipeline_id == "extract-fields"
      assert route.destination_id == "s3-archive"
      assert route.position == 1
      assert is_function(route.filter, 1)
    end

    test "defaults final to true" do
      route = Route.new(valid_attrs())
      assert route.final == true
    end

    test "defaults enabled to true" do
      route = Route.new(valid_attrs())
      assert route.enabled == true
    end

    test "defaults description to nil" do
      route = Route.new(valid_attrs())
      assert route.description == nil
    end

    test "allows overriding final" do
      route = Route.new(valid_attrs(final: false))
      assert route.final == false
    end

    test "allows overriding enabled" do
      route = Route.new(valid_attrs(enabled: false))
      assert route.enabled == false
    end

    test "allows setting description" do
      route = Route.new(valid_attrs(description: "Apache web logs"))
      assert route.description == "Apache web logs"
    end

    test "raises when required fields are missing" do
      assert_raise ArgumentError, fn ->
        Route.new(id: "route-1", name: "incomplete")
      end
    end
  end

  describe "matches?/2" do
    test "returns true when filter matches" do
      route =
        Route.new(
          valid_attrs(
            filter: fn event -> Map.get(event, "source") == "apache" end
          )
        )

      event = %{"source" => "apache", "_raw" => "", "_time" => 0}
      assert Route.matches?(route, event) == true
    end

    test "returns false when filter does not match" do
      route =
        Route.new(
          valid_attrs(
            filter: fn event -> Map.get(event, "source") == "apache" end
          )
        )

      event = %{"source" => "nginx", "_raw" => "", "_time" => 0}
      assert Route.matches?(route, event) == false
    end

    test "catch-all filter matches any event" do
      route = Route.new(valid_attrs(filter: fn _event -> true end))

      event = %{"anything" => "goes", "_raw" => "", "_time" => 0}
      assert Route.matches?(route, event) == true
    end
  end
end
