defmodule CompressrWeb.Api.FallbackControllerTest do
  use CompressrWeb.ConnCase, async: true

  alias CompressrWeb.Api.FallbackController

  describe "call/2" do
    test "handles {:error, :not_found}", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :not_found})

      assert conn.status == 404
      assert Jason.decode!(conn.resp_body) == %{"error" => "not_found"}
    end

    test "handles {:error, {:missing_fields, fields}}", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, {:missing_fields, ["name", "type"]}})

      assert conn.status == 422
      body = Jason.decode!(conn.resp_body)
      assert body["error"] == "validation_error"
      assert body["details"]["missing_fields"] == ["name", "type"]
    end

    test "handles {:error, :unknown_type}", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :unknown_type})

      assert conn.status == 422
      body = Jason.decode!(conn.resp_body)
      assert body["error"] == "validation_error"
      assert body["details"]["message"] == "unknown type"
    end

    test "handles {:error, binary_reason}", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, "something went wrong"})

      assert conn.status == 422
      body = Jason.decode!(conn.resp_body)
      assert body["error"] == "validation_error"
      assert body["details"]["message"] == "something went wrong"
    end

    test "handles {:error, non_binary_reason} as 500", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :some_atom_reason})

      assert conn.status == 500
      body = Jason.decode!(conn.resp_body)
      assert body["error"] == "internal_server_error"
    end

    test "handles {:error, tuple_reason} as 500", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, {:unexpected, "details"}})

      assert conn.status == 500
      body = Jason.decode!(conn.resp_body)
      assert body["error"] == "internal_server_error"
    end

    test "handles {:error, {:missing_fields, []}} with empty list", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, {:missing_fields, []}})

      assert conn.status == 422
      body = Jason.decode!(conn.resp_body)
      assert body["details"]["missing_fields"] == []
    end

    test "handles {:error, empty_string}", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, ""})

      assert conn.status == 422
      body = Jason.decode!(conn.resp_body)
      assert body["error"] == "validation_error"
      assert body["details"]["message"] == ""
    end
  end
end
