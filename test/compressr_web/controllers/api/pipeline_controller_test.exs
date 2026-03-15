defmodule CompressrWeb.Api.PipelineControllerTest do
  use CompressrWeb.ConnCase, async: false

  alias Compressr.Pipeline.Config

  setup do
    clean_items("pipeline")
    :ok
  end

  describe "GET /api/v1/system/pipelines" do
    test "returns empty list when no pipelines exist", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/system/pipelines")

      assert %{"items" => [], "count" => 0} = json_response(conn, 200)
    end

    test "returns all pipelines", %{conn: conn} do
      {:ok, _} = Config.save(valid_pipeline("pipe-1"))
      {:ok, _} = Config.save(valid_pipeline("pipe-2"))

      conn = get(conn, ~p"/api/v1/system/pipelines")

      response = json_response(conn, 200)
      assert response["count"] == 2
      assert length(response["items"]) == 2
    end
  end

  describe "GET /api/v1/system/pipelines/:id" do
    test "returns pipeline when found", %{conn: conn} do
      {:ok, _} = Config.save(valid_pipeline("pipe-show"))

      conn = get(conn, ~p"/api/v1/system/pipelines/pipe-show")

      response = json_response(conn, 200)
      assert response["count"] == 1
      assert [item] = response["items"]
      assert item["id"] == "pipe-show"
      assert item["name"] == "Test Pipeline"
    end

    test "returns 404 when not found", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/system/pipelines/nonexistent")

      assert %{"error" => "not_found"} = json_response(conn, 404)
    end
  end

  describe "POST /api/v1/system/pipelines" do
    test "creates a pipeline with valid params", %{conn: conn} do
      params = %{
        "id" => "pipe-create",
        "name" => "New Pipeline",
        "functions" => [%{"type" => "rename", "config" => %{}}]
      }

      conn = post(conn, ~p"/api/v1/system/pipelines", params)

      response = json_response(conn, 201)
      assert response["count"] == 1
      assert [item] = response["items"]
      assert item["id"] == "pipe-create"
      assert item["name"] == "New Pipeline"
    end

    test "returns 422 for missing required fields", %{conn: conn} do
      params = %{"id" => "bad-pipe"}

      conn = post(conn, ~p"/api/v1/system/pipelines", params)

      assert response = json_response(conn, 422)
      assert response["error"] == "validation_error"
    end

    test "generates an id if not provided", %{conn: conn} do
      params = %{
        "name" => "Auto ID Pipeline",
        "functions" => []
      }

      conn = post(conn, ~p"/api/v1/system/pipelines", params)

      response = json_response(conn, 201)
      assert [item] = response["items"]
      assert is_binary(item["id"])
      assert String.length(item["id"]) > 0
    end
  end

  describe "PATCH /api/v1/system/pipelines/:id" do
    test "updates an existing pipeline", %{conn: conn} do
      {:ok, _} = Config.save(valid_pipeline("pipe-update"))

      params = %{"name" => "Updated Pipeline"}
      conn = patch(conn, ~p"/api/v1/system/pipelines/pipe-update", params)

      response = json_response(conn, 200)
      assert [item] = response["items"]
      assert item["name"] == "Updated Pipeline"
      assert item["id"] == "pipe-update"
    end

    test "returns 404 when pipeline not found", %{conn: conn} do
      conn = patch(conn, ~p"/api/v1/system/pipelines/nonexistent", %{"name" => "X"})

      assert %{"error" => "not_found"} = json_response(conn, 404)
    end
  end

  describe "DELETE /api/v1/system/pipelines/:id" do
    test "deletes an existing pipeline", %{conn: conn} do
      {:ok, _} = Config.save(valid_pipeline("pipe-delete"))

      conn = delete(conn, ~p"/api/v1/system/pipelines/pipe-delete")

      assert %{"items" => [], "count" => 0} = json_response(conn, 200)
      assert {:ok, nil} = Config.get("pipe-delete")
    end

    test "returns 404 when pipeline not found", %{conn: conn} do
      conn = delete(conn, ~p"/api/v1/system/pipelines/nonexistent")

      assert %{"error" => "not_found"} = json_response(conn, 404)
    end
  end

  # --- Helpers ---

  defp valid_pipeline(id) do
    %{
      "id" => id,
      "name" => "Test Pipeline",
      "functions" => [%{"type" => "rename", "config" => %{}}]
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
