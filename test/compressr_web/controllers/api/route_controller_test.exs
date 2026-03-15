defmodule CompressrWeb.Api.RouteControllerTest do
  use CompressrWeb.ConnCase, async: false

  alias Compressr.Routing.Config

  setup do
    clean_items("route")
    :ok
  end

  describe "GET /api/v1/system/routes" do
    test "returns empty list when no routes exist", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/system/routes")

      assert %{"items" => [], "count" => 0} = json_response(conn, 200)
    end

    test "returns all routes", %{conn: conn} do
      {:ok, _} = Config.save(valid_route("route-1"))
      {:ok, _} = Config.save(valid_route("route-2"))

      conn = get(conn, ~p"/api/v1/system/routes")

      response = json_response(conn, 200)
      assert response["count"] == 2
      assert length(response["items"]) == 2
    end
  end

  describe "GET /api/v1/system/routes/:id" do
    test "returns route when found", %{conn: conn} do
      {:ok, _} = Config.save(valid_route("route-show"))

      conn = get(conn, ~p"/api/v1/system/routes/route-show")

      response = json_response(conn, 200)
      assert response["count"] == 1
      assert [item] = response["items"]
      assert item["id"] == "route-show"
      assert item["name"] == "Test Route"
    end

    test "returns 404 when not found", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/system/routes/nonexistent")

      assert %{"error" => "not_found"} = json_response(conn, 404)
    end
  end

  describe "POST /api/v1/system/routes" do
    test "creates a route with valid params", %{conn: conn} do
      params = %{
        "id" => "route-create",
        "name" => "New Route",
        "filter" => "source == 'syslog'",
        "pipeline_id" => "pipeline-1",
        "destination_id" => "dest-1",
        "position" => 10
      }

      conn = post(conn, ~p"/api/v1/system/routes", params)

      response = json_response(conn, 201)
      assert response["count"] == 1
      assert [item] = response["items"]
      assert item["id"] == "route-create"
      assert item["name"] == "New Route"
    end

    test "returns 422 for missing required fields", %{conn: conn} do
      params = %{"id" => "bad-route", "name" => "Missing Fields"}

      conn = post(conn, ~p"/api/v1/system/routes", params)

      assert response = json_response(conn, 422)
      assert response["error"] == "validation_error"
    end

    test "generates an id if not provided", %{conn: conn} do
      params = %{
        "name" => "Auto ID Route",
        "filter" => "true",
        "pipeline_id" => "pipe-1",
        "destination_id" => "dest-1"
      }

      conn = post(conn, ~p"/api/v1/system/routes", params)

      response = json_response(conn, 201)
      assert [item] = response["items"]
      assert is_binary(item["id"])
      assert String.length(item["id"]) > 0
    end
  end

  describe "PATCH /api/v1/system/routes/:id" do
    test "updates an existing route", %{conn: conn} do
      {:ok, _} = Config.save(valid_route("route-update"))

      params = %{"name" => "Updated Route"}
      conn = patch(conn, ~p"/api/v1/system/routes/route-update", params)

      response = json_response(conn, 200)
      assert [item] = response["items"]
      assert item["name"] == "Updated Route"
      assert item["id"] == "route-update"
    end

    test "returns 404 when route not found", %{conn: conn} do
      conn = patch(conn, ~p"/api/v1/system/routes/nonexistent", %{"name" => "X"})

      assert %{"error" => "not_found"} = json_response(conn, 404)
    end
  end

  describe "DELETE /api/v1/system/routes/:id" do
    test "deletes an existing route", %{conn: conn} do
      {:ok, _} = Config.save(valid_route("route-delete"))

      conn = delete(conn, ~p"/api/v1/system/routes/route-delete")

      assert %{"items" => [], "count" => 0} = json_response(conn, 200)
      assert {:ok, nil} = Config.get("route-delete")
    end

    test "returns 404 when route not found", %{conn: conn} do
      conn = delete(conn, ~p"/api/v1/system/routes/nonexistent")

      assert %{"error" => "not_found"} = json_response(conn, 404)
    end
  end

  # --- Helpers ---

  defp valid_route(id) do
    %{
      "id" => id,
      "name" => "Test Route",
      "filter" => "source == 'syslog'",
      "pipeline_id" => "pipeline-1",
      "destination_id" => "dest-1",
      "position" => 0
    }
  end

  defp clean_items(pk_value) do
    table = "compressr_test_config"

    # expression_attribute_values keys get ":" auto-prepended by ex_aws_dynamo
    result =
      ExAws.Dynamo.scan(table,
        filter_expression: "pk = :pk",
        expression_attribute_values: %{"pk" => pk_value}
      )
      |> ExAws.request!()

    items = Map.get(result, "Items", [])

    Enum.each(items, fn item ->
      pk = get_in(item, ["pk", "S"])
      sk = get_in(item, ["sk", "S"])
      ExAws.Dynamo.delete_item(table, %{"pk" => pk, "sk" => sk}) |> ExAws.request!()
    end)
  end
end
