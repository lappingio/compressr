defmodule CompressrWeb.AuthControllerTest do
  use CompressrWeb.ConnCase, async: true

  describe "GET /auth/login" do
    test "renders the login page", %{conn: conn} do
      conn = get(conn, "/auth/login")
      assert conn.status == 200
      assert conn.resp_body =~ "Login"
      assert conn.resp_body =~ "Google"
    end
  end

  describe "GET /auth/callback" do
    test "returns placeholder response", %{conn: conn} do
      conn = get(conn, "/auth/callback")
      assert conn.status == 200
      assert conn.resp_body =~ "OIDC callback placeholder"
    end
  end

  describe "GET /auth/logout" do
    test "clears session and redirects to login", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{current_user: %{sub: "test"}})
        |> get("/auth/logout")

      assert redirected_to(conn) == "/auth/login"
    end
  end
end
