defmodule CompressrWeb.Api.DestinationControllerTest do
  use CompressrWeb.ConnCase, async: false

  alias Compressr.Destination.Config

  setup do
    clean_items("destination")
    :ok
  end

  describe "GET /api/v1/system/outputs" do
    test "returns empty list when no destinations exist", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/system/outputs")

      assert %{"items" => [], "count" => 0} = json_response(conn, 200)
    end

    test "returns all destinations", %{conn: conn} do
      {:ok, _} = Config.save(valid_dest("dest-1"))
      {:ok, _} = Config.save(valid_dest("dest-2"))

      conn = get(conn, ~p"/api/v1/system/outputs")

      response = json_response(conn, 200)
      assert response["count"] == 2
      assert length(response["items"]) == 2
    end
  end

  describe "GET /api/v1/system/outputs/:id" do
    test "returns destination when found", %{conn: conn} do
      {:ok, _} = Config.save(valid_dest("dest-show"))

      conn = get(conn, ~p"/api/v1/system/outputs/dest-show")

      response = json_response(conn, 200)
      assert response["count"] == 1
      assert [item] = response["items"]
      assert item["id"] == "dest-show"
      assert item["name"] == "Test Destination"
    end

    test "returns 404 when not found", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/system/outputs/nonexistent")

      assert %{"error" => "not_found"} = json_response(conn, 404)
    end
  end

  describe "POST /api/v1/system/outputs" do
    test "creates a destination with valid params", %{conn: conn} do
      params = %{
        "id" => "dest-create",
        "name" => "New Dest",
        "type" => "s3",
        "config" => %{"bucket" => "test-bucket"},
        "enabled" => true
      }

      conn = post(conn, ~p"/api/v1/system/outputs", params)

      response = json_response(conn, 201)
      assert response["count"] == 1
      assert [item] = response["items"]
      assert item["id"] == "dest-create"
      assert item["name"] == "New Dest"
    end

    test "generates an id if not provided", %{conn: conn} do
      params = %{
        "name" => "Auto ID Dest",
        "type" => "devnull",
        "config" => %{}
      }

      conn = post(conn, ~p"/api/v1/system/outputs", params)

      response = json_response(conn, 201)
      assert [item] = response["items"]
      assert is_binary(item["id"])
      assert String.length(item["id"]) > 0
    end
  end

  describe "PATCH /api/v1/system/outputs/:id" do
    test "updates an existing destination", %{conn: conn} do
      {:ok, _} = Config.save(valid_dest("dest-update"))

      params = %{"name" => "Updated Dest Name"}
      conn = patch(conn, ~p"/api/v1/system/outputs/dest-update", params)

      response = json_response(conn, 200)
      assert [item] = response["items"]
      assert item["name"] == "Updated Dest Name"
      assert item["id"] == "dest-update"
    end

    test "returns 404 when destination not found", %{conn: conn} do
      conn = patch(conn, ~p"/api/v1/system/outputs/nonexistent", %{"name" => "X"})

      assert %{"error" => "not_found"} = json_response(conn, 404)
    end
  end

  describe "DELETE /api/v1/system/outputs/:id" do
    test "deletes an existing destination", %{conn: conn} do
      {:ok, _} = Config.save(valid_dest("dest-delete"))

      conn = delete(conn, ~p"/api/v1/system/outputs/dest-delete")

      assert %{"items" => [], "count" => 0} = json_response(conn, 200)
      assert {:ok, nil} = Config.get("dest-delete")
    end

    test "returns 404 when destination not found", %{conn: conn} do
      conn = delete(conn, ~p"/api/v1/system/outputs/nonexistent")

      assert %{"error" => "not_found"} = json_response(conn, 404)
    end
  end

  # --- Helpers ---

  defp valid_dest(id) do
    %Config{
      id: id,
      name: "Test Destination",
      type: "s3",
      config: %{"bucket" => "test-bucket"},
      enabled: true,
      backpressure_mode: :block
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
