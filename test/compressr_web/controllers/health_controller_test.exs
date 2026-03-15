defmodule CompressrWeb.HealthControllerTest do
  use CompressrWeb.ConnCase, async: true

  describe "GET /health" do
    test "returns 200 with JSON health data", %{conn: conn} do
      conn = get(conn, ~p"/health")

      assert response = json_response(conn, 200)
      assert response["status"] == "healthy"
      assert is_binary(response["node"])
      assert is_integer(response["uptime_seconds"])
      assert is_number(response["memory_mb"])
      assert is_integer(response["connected_peers"])
    end

    test "requires no authentication", %{conn: conn} do
      conn = get(conn, ~p"/health")
      refute conn.status in [401, 403]
    end

    test "returns JSON content type", %{conn: conn} do
      conn = get(conn, ~p"/health")
      assert {"content-type", content_type} = List.keyfind(conn.resp_headers, "content-type", 0)
      assert content_type =~ "application/json"
    end
  end

  describe "GET /ready" do
    test "returns JSON with readiness data", %{conn: conn} do
      conn = get(conn, ~p"/ready")

      response = json_response(conn, conn.status)
      assert response["status"] in ["ready", "not_ready"]
      assert is_binary(response["node"])
      assert is_map(response["subsystems"])
    end

    test "requires no authentication", %{conn: conn} do
      conn = get(conn, ~p"/ready")
      refute conn.status in [401, 403]
    end

    test "returns 200 when all subsystems are ready", %{conn: conn} do
      # Register a subsystem as ready
      Compressr.Health.Readiness.report_ready(:endpoint)

      conn = get(conn, ~p"/ready")
      assert json_response(conn, 200)["status"] == "ready"
    end

    test "returns JSON content type", %{conn: conn} do
      conn = get(conn, ~p"/ready")
      assert {"content-type", content_type} = List.keyfind(conn.resp_headers, "content-type", 0)
      assert content_type =~ "application/json"
    end
  end
end
