defmodule CompressrWeb.Api.AuditControllerTest do
  use CompressrWeb.ConnCase, async: false

  alias Compressr.Audit

  setup do
    clean_audit_items()

    # Pre-populate some audit events
    user = %{user_id: "ctrl-user", user_email: "ctrl@example.com"}

    {:ok, _} =
      Audit.log(:login, user, %{source_ip: "10.0.0.1"})

    {:ok, _} =
      Audit.log(:config_created, user, %{
        resource_type: "source",
        resource_id: "src-abc",
        details: %{"name" => "Test Source"}
      })

    {:ok, _} =
      Audit.log(:config_deleted, %{user_id: "other-user", user_email: "other@example.com"}, %{
        resource_type: "destination",
        resource_id: "dst-xyz"
      })

    {:ok, user: user}
  end

  describe "GET /api/v1/system/audit" do
    test "returns audit events for today", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/system/audit")

      response = json_response(conn, 200)
      assert is_list(response["items"])
      assert response["count"] >= 3
    end

    test "filters by date parameter", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/system/audit?date=2020-01-01")

      response = json_response(conn, 200)
      assert response["items"] == []
      assert response["count"] == 0
    end

    test "filters by user_id parameter", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/system/audit?user_id=ctrl-user")

      response = json_response(conn, 200)
      assert response["count"] >= 2

      Enum.each(response["items"], fn item ->
        assert item["user_id"] == "ctrl-user"
      end)
    end

    test "filters by resource_type and resource_id", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/system/audit?resource_type=source&resource_id=src-abc")

      response = json_response(conn, 200)
      assert response["count"] >= 1

      Enum.each(response["items"], fn item ->
        assert item["resource_type"] == "source"
        assert item["resource_id"] == "src-abc"
      end)
    end

    test "respects limit parameter", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/system/audit?limit=1")

      response = json_response(conn, 200)
      assert response["count"] <= 1
    end

    test "returns event fields in expected format", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/system/audit?user_id=ctrl-user")

      response = json_response(conn, 200)
      assert response["count"] >= 1
      [item | _] = response["items"]

      assert Map.has_key?(item, "id")
      assert Map.has_key?(item, "timestamp")
      assert Map.has_key?(item, "action")
      assert Map.has_key?(item, "user_id")
      assert Map.has_key?(item, "user_email")
    end
  end

  defp clean_audit_items do
    result =
      ExAws.Dynamo.scan("compressr_test_audit",
        filter_expression: "begins_with(pk, :prefix)",
        expression_attribute_values: [prefix: "audit#"]
      )
      |> ExAws.request!()

    items = Map.get(result, "Items", [])

    Enum.each(items, fn item ->
      pk = get_in(item, ["pk", "S"])
      sk = get_in(item, ["sk", "S"])

      if pk && sk do
        ExAws.Dynamo.delete_item("compressr_test_audit", %{"pk" => pk, "sk" => sk})
        |> ExAws.request!()
      end
    end)
  end
end
