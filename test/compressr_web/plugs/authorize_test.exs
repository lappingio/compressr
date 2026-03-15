defmodule CompressrWeb.Plugs.AuthorizeTest do
  use CompressrWeb.ConnCase, async: true

  alias CompressrWeb.Plugs.Authorize
  alias Compressr.Auth.User

  defp build_user(role) do
    %User{
      sub: "auth-test-user",
      email: "authtest@example.com",
      provider: "google",
      role: role,
      display_name: "Auth Test"
    }
  end

  describe "authorized request" do
    test "admin passes through for manage user", %{conn: conn} do
      opts = Authorize.init(action: :manage, resource: :user)

      conn =
        conn
        |> assign(:current_user, build_user(:admin))
        |> Authorize.call(opts)

      refute conn.halted
    end

    test "viewer passes through for list source", %{conn: conn} do
      opts = Authorize.init(action: :list, resource: :source)

      conn =
        conn
        |> assign(:current_user, build_user(:viewer))
        |> Authorize.call(opts)

      refute conn.halted
    end

    test "editor passes through for create source", %{conn: conn} do
      opts = Authorize.init(action: :create, resource: :source)

      conn =
        conn
        |> assign(:current_user, build_user(:editor))
        |> Authorize.call(opts)

      refute conn.halted
    end
  end

  describe "unauthorized request" do
    test "viewer gets 403 for create source (JSON)", %{conn: conn} do
      opts = Authorize.init(action: :create, resource: :source)

      conn =
        conn
        |> put_req_header("accept", "application/json")
        |> assign(:current_user, build_user(:viewer))
        |> Authorize.call(opts)

      assert conn.halted
      assert conn.status == 403
      assert Jason.decode!(conn.resp_body) == %{"error" => "forbidden"}
    end

    test "editor gets 403 for manage user (JSON)", %{conn: conn} do
      opts = Authorize.init(action: :manage, resource: :user)

      conn =
        conn
        |> put_req_header("accept", "application/json")
        |> assign(:current_user, build_user(:editor))
        |> Authorize.call(opts)

      assert conn.halted
      assert conn.status == 403
    end

    test "viewer gets 403 HTML for delete source (HTML)", %{conn: conn} do
      opts = Authorize.init(action: :delete, resource: :source)

      conn =
        conn
        |> put_req_header("accept", "text/html")
        |> assign(:current_user, build_user(:viewer))
        |> Authorize.call(opts)

      assert conn.halted
      assert conn.status == 403
      assert conn.resp_body =~ "403 Forbidden"
    end
  end

  describe "missing user" do
    test "returns 401 JSON when no current_user", %{conn: conn} do
      opts = Authorize.init(action: :list, resource: :source)

      conn =
        conn
        |> put_req_header("accept", "application/json")
        |> Authorize.call(opts)

      assert conn.halted
      assert conn.status == 401
      assert Jason.decode!(conn.resp_body) == %{"error" => "unauthorized"}
    end

    test "redirects to login when no current_user (HTML)", %{conn: conn} do
      opts = Authorize.init(action: :list, resource: :source)

      conn =
        conn
        |> put_req_header("accept", "text/html")
        |> Authorize.call(opts)

      assert conn.halted
      assert redirected_to(conn) == "/auth/login"
    end
  end

  describe "init/1" do
    test "requires action and resource options" do
      assert_raise KeyError, fn ->
        Authorize.init([])
      end

      assert_raise KeyError, fn ->
        Authorize.init(action: :list)
      end
    end
  end
end
