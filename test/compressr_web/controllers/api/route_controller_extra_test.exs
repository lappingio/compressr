defmodule CompressrWeb.Api.RouteControllerExtraTest do
  use CompressrWeb.ConnCase, async: false

  alias Compressr.Routing.Config

  setup do
    clean_items("route")
    :ok
  end

  describe "POST /api/v1/system/routes with edge cases" do
    test "creates route with enabled=false", %{conn: conn} do
      params = %{
        "id" => "route-disabled",
        "name" => "Disabled Route",
        "filter" => "true",
        "pipeline_id" => "pipe-1",
        "destination_id" => "dest-1",
        "enabled" => false
      }

      conn = post(conn, ~p"/api/v1/system/routes", params)
      response = json_response(conn, 201)
      assert [item] = response["items"]
      assert item["enabled"] == false
    end

    test "creates route with final=false", %{conn: conn} do
      params = %{
        "id" => "route-nonfinal",
        "name" => "Non-final Route",
        "filter" => "true",
        "pipeline_id" => "pipe-1",
        "destination_id" => "dest-1",
        "final" => false
      }

      conn = post(conn, ~p"/api/v1/system/routes", params)
      response = json_response(conn, 201)
      assert [item] = response["items"]
      assert item["final"] == false
    end

    test "creates route with description", %{conn: conn} do
      params = %{
        "id" => "route-desc",
        "name" => "Described Route",
        "filter" => "source == 'apache'",
        "pipeline_id" => "pipe-1",
        "destination_id" => "dest-1",
        "description" => "Routes apache logs"
      }

      conn = post(conn, ~p"/api/v1/system/routes", params)
      response = json_response(conn, 201)
      assert [item] = response["items"]
      assert item["description"] == "Routes apache logs"
    end

    test "creates route with custom position", %{conn: conn} do
      params = %{
        "id" => "route-pos",
        "name" => "Positioned Route",
        "filter" => "true",
        "pipeline_id" => "pipe-1",
        "destination_id" => "dest-1",
        "position" => 42
      }

      conn = post(conn, ~p"/api/v1/system/routes", params)
      response = json_response(conn, 201)
      assert [item] = response["items"]
      assert item["position"] == 42
    end

    test "returns error when name is empty", %{conn: conn} do
      params = %{
        "id" => "route-no-name",
        "name" => "",
        "pipeline_id" => "p",
        "destination_id" => "d"
      }

      conn = post(conn, ~p"/api/v1/system/routes", params)
      assert json_response(conn, 422)
    end
  end

  describe "PATCH /api/v1/system/routes/:id edge cases" do
    test "updates filter", %{conn: conn} do
      {:ok, _} = Config.save(%{
        "id" => "route-upd-filter",
        "name" => "Filter Route",
        "filter" => "true",
        "pipeline_id" => "pipe-1",
        "destination_id" => "dest-1"
      })

      params = %{"filter" => "source == 'nginx'"}
      conn = patch(conn, ~p"/api/v1/system/routes/route-upd-filter", params)
      response = json_response(conn, 200)
      assert [item] = response["items"]
      assert item["filter"] == "source == 'nginx'"
    end

    test "updates position", %{conn: conn} do
      {:ok, _} = Config.save(%{
        "id" => "route-upd-pos",
        "name" => "Position Route",
        "filter" => "true",
        "pipeline_id" => "pipe-1",
        "destination_id" => "dest-1",
        "position" => 1
      })

      params = %{"position" => 99}
      conn = patch(conn, ~p"/api/v1/system/routes/route-upd-pos", params)
      response = json_response(conn, 200)
      assert [item] = response["items"]
      assert item["position"] == 99
    end

    test "updates enabled flag", %{conn: conn} do
      {:ok, _} = Config.save(%{
        "id" => "route-upd-en",
        "name" => "Enable Route",
        "filter" => "true",
        "pipeline_id" => "pipe-1",
        "destination_id" => "dest-1"
      })

      params = %{"enabled" => false}
      conn = patch(conn, ~p"/api/v1/system/routes/route-upd-en", params)
      response = json_response(conn, 200)
      assert [item] = response["items"]
      assert item["enabled"] == false
    end

    test "updates destination_id", %{conn: conn} do
      {:ok, _} = Config.save(%{
        "id" => "route-upd-dest",
        "name" => "Dest Route",
        "filter" => "true",
        "pipeline_id" => "pipe-1",
        "destination_id" => "dest-1"
      })

      params = %{"destination_id" => "dest-2"}
      conn = patch(conn, ~p"/api/v1/system/routes/route-upd-dest", params)
      response = json_response(conn, 200)
      assert [item] = response["items"]
      assert item["destination_id"] == "dest-2"
    end
  end

  defp clean_items(pk_value) do
    table = "compressr_test_config"

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
