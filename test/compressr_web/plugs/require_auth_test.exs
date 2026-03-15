defmodule CompressrWeb.Plugs.RequireAuthTest do
  use CompressrWeb.ConnCase, async: false

  alias CompressrWeb.Plugs.RequireAuth
  alias Compressr.Auth.{User, ApiToken}

  setup do
    clean_items()

    {:ok, user} =
      User.find_or_create(%{
        sub: "plug-test-user",
        email: "plugtest@example.com",
        display_name: "Plug Test",
        provider: "google"
      })

    {:ok, user: user}
  end

  describe "session-based authentication" do
    test "passes through when user is in session", %{conn: conn, user: user} do
      user_data = %{
        "sub" => user.sub,
        "email" => user.email,
        "display_name" => user.display_name,
        "provider" => user.provider,
        "role" => "viewer",
        "inserted_at" => user.inserted_at,
        "updated_at" => user.updated_at
      }

      conn =
        conn
        |> init_test_session(%{current_user: user_data})
        |> RequireAuth.call([])

      assert conn.assigns.current_user.sub == user.sub
      refute conn.halted
    end
  end

  describe "Bearer token authentication" do
    test "passes through with valid Bearer token", %{conn: conn, user: user} do
      {:ok, raw_token} = ApiToken.create(user)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{raw_token}")
        |> init_test_session(%{})
        |> RequireAuth.call([])

      assert conn.assigns.current_user.sub == user.sub
      refute conn.halted
    end

    test "rejects invalid Bearer token", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer cpr_invalid")
        |> put_req_header("accept", "application/json")
        |> init_test_session(%{})
        |> RequireAuth.call([])

      assert conn.halted
      assert conn.status == 401
    end
  end

  describe "unauthenticated requests" do
    test "returns 401 for JSON requests", %{conn: conn} do
      conn =
        conn
        |> put_req_header("accept", "application/json")
        |> init_test_session(%{})
        |> RequireAuth.call([])

      assert conn.halted
      assert conn.status == 401
      assert Jason.decode!(conn.resp_body) == %{"error" => "unauthorized"}
    end

    test "redirects HTML requests to /auth/login", %{conn: conn} do
      conn =
        conn
        |> put_req_header("accept", "text/html")
        |> init_test_session(%{})
        |> RequireAuth.call([])

      assert conn.halted
      assert redirected_to(conn) == "/auth/login"
    end
  end

  defp clean_items do
    for {expr, vals} <- [
          {"pk = :pk", [pk: "api_token"]},
          {"begins_with(pk, :prefix)", [prefix: "user#"]}
        ] do
      result =
        ExAws.Dynamo.scan("compressr_test_config",
          filter_expression: expr,
          expression_attribute_values: vals
        )
        |> ExAws.request!()

      items = Map.get(result, "Items", [])

      Enum.each(items, fn item ->
        pk = get_in(item, ["pk", "S"])
        sk = get_in(item, ["sk", "S"])

        ExAws.Dynamo.delete_item("compressr_test_config", %{"pk" => pk, "sk" => sk})
        |> ExAws.request!()
      end)
    end
  end
end
