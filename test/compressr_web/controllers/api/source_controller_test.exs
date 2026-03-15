defmodule CompressrWeb.Api.SourceControllerTest do
  use CompressrWeb.ConnCase, async: false

  alias Compressr.Source.Config

  setup do
    clean_items("source")
    :ok
  end

  describe "GET /api/v1/system/inputs" do
    test "returns empty list when no sources exist", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/system/inputs")

      assert %{"items" => [], "count" => 0} = json_response(conn, 200)
    end

    test "returns all sources", %{conn: conn} do
      {:ok, _} = Config.save(valid_syslog_config("src-1"))
      {:ok, _} = Config.save(valid_syslog_config("src-2"))

      conn = get(conn, ~p"/api/v1/system/inputs")

      response = json_response(conn, 200)
      assert response["count"] == 2
      assert length(response["items"]) == 2
    end
  end

  describe "GET /api/v1/system/inputs/:id" do
    test "returns source when found", %{conn: conn} do
      {:ok, _} = Config.save(valid_syslog_config("src-show"))

      conn = get(conn, ~p"/api/v1/system/inputs/src-show")

      response = json_response(conn, 200)
      assert response["count"] == 1
      assert [item] = response["items"]
      assert item["id"] == "src-show"
      assert item["name"] == "Test Syslog"
    end

    test "returns 404 when not found", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/system/inputs/nonexistent")

      assert %{"error" => "not_found"} = json_response(conn, 404)
    end
  end

  describe "POST /api/v1/system/inputs" do
    test "creates a source with valid params", %{conn: conn} do
      params = %{
        "id" => "src-create",
        "name" => "New Syslog",
        "type" => "syslog",
        "config" => %{"udp_port" => 5514, "protocol" => "udp"}
      }

      conn = post(conn, ~p"/api/v1/system/inputs", params)

      response = json_response(conn, 201)
      assert response["count"] == 1
      assert [item] = response["items"]
      assert item["id"] == "src-create"
      assert item["name"] == "New Syslog"
    end

    test "returns 422 for missing required fields", %{conn: conn} do
      params = %{"id" => "bad-source"}

      conn = post(conn, ~p"/api/v1/system/inputs", params)

      assert response = json_response(conn, 422)
      assert response["error"] == "validation_error"
    end

    test "generates an id if not provided", %{conn: conn} do
      params = %{
        "name" => "Auto ID Source",
        "type" => "syslog",
        "config" => %{"udp_port" => 5514, "protocol" => "udp"}
      }

      conn = post(conn, ~p"/api/v1/system/inputs", params)

      response = json_response(conn, 201)
      assert [item] = response["items"]
      assert is_binary(item["id"])
      assert String.length(item["id"]) > 0
    end
  end

  describe "PATCH /api/v1/system/inputs/:id" do
    test "updates an existing source", %{conn: conn} do
      {:ok, _} = Config.save(valid_syslog_config("src-update"))

      params = %{"name" => "Updated Name"}
      conn = patch(conn, ~p"/api/v1/system/inputs/src-update", params)

      response = json_response(conn, 200)
      assert [item] = response["items"]
      assert item["name"] == "Updated Name"
      assert item["id"] == "src-update"
    end

    test "returns 404 when source not found", %{conn: conn} do
      conn = patch(conn, ~p"/api/v1/system/inputs/nonexistent", %{"name" => "X"})

      assert %{"error" => "not_found"} = json_response(conn, 404)
    end
  end

  describe "DELETE /api/v1/system/inputs/:id" do
    test "deletes an existing source", %{conn: conn} do
      {:ok, _} = Config.save(valid_syslog_config("src-delete"))

      conn = delete(conn, ~p"/api/v1/system/inputs/src-delete")

      assert %{"items" => [], "count" => 0} = json_response(conn, 200)

      # Verify it's actually gone
      assert {:ok, nil} = Config.get("src-delete")
    end

    test "returns 404 when source not found", %{conn: conn} do
      conn = delete(conn, ~p"/api/v1/system/inputs/nonexistent")

      assert %{"error" => "not_found"} = json_response(conn, 404)
    end
  end

  # --- Helpers ---

  defp valid_syslog_config(id) do
    %{
      "id" => id,
      "name" => "Test Syslog",
      "type" => "syslog",
      "config" => %{"udp_port" => 5514, "protocol" => "udp"}
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
