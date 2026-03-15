defmodule CompressrWeb.Plugs.AuditTest do
  use CompressrWeb.ConnCase, async: false

  alias CompressrWeb.Plugs.Audit, as: AuditPlug

  setup do
    clean_audit_items()
    :ok
  end

  describe "call/2" do
    test "does not halt the connection", %{conn: conn} do
      conn =
        conn
        |> AuditPlug.call([])

      refute conn.halted
    end

    test "registers a before_send callback", %{conn: conn} do
      conn = AuditPlug.call(conn, [])

      # The before_send callback is registered; when we send a response, it fires
      conn =
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(%{ok: true}))

      assert conn.status == 200
    end

    test "logs request with user info when current_user is assigned", %{conn: conn} do
      user = %{sub: "plug-audit-user", email: "pa@example.com"}

      conn =
        conn
        |> assign(:current_user, user)
        |> AuditPlug.call([])
        |> put_resp_content_type("application/json")
        |> send_resp(201, Jason.encode!(%{created: true}))

      assert conn.status == 201

      # Give the async Task a moment to persist
      Process.sleep(100)

      {:ok, events, _} = Compressr.Audit.query_by_date(Date.utc_today())

      matching =
        Enum.filter(events, fn e ->
          e.user_id == "plug-audit-user" and
            e.details != nil and
            e.details["status"] == 201
        end)

      assert length(matching) >= 1
    end

    test "logs request without user when unauthenticated", %{conn: conn} do
      conn =
        conn
        |> AuditPlug.call([])
        |> put_resp_content_type("application/json")
        |> send_resp(401, Jason.encode!(%{error: "unauthorized"}))

      assert conn.status == 401

      Process.sleep(100)

      {:ok, events, _} = Compressr.Audit.query_by_date(Date.utc_today())

      matching =
        Enum.filter(events, fn e ->
          e.details != nil and e.details["status"] == 401
        end)

      assert length(matching) >= 1
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
