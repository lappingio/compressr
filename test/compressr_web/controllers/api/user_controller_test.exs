defmodule CompressrWeb.Api.UserControllerTest do
  use CompressrWeb.ConnCase, async: false

  alias Compressr.Auth.User

  setup do
    clean_items()

    # Create users in DynamoDB for listing/showing
    {:ok, admin_user} =
      User.find_or_create(%{
        sub: "admin-user",
        email: "admin@example.com",
        display_name: "Admin User",
        provider: "google"
      })

    {:ok, admin_user} = User.update_role(admin_user, :admin)

    {:ok, viewer_user} =
      User.find_or_create(%{
        sub: "viewer-user",
        email: "viewer@example.com",
        display_name: "Viewer User",
        provider: "google"
      })

    {:ok, editor_user} =
      User.find_or_create(%{
        sub: "editor-user",
        email: "editor@example.com",
        display_name: "Editor User",
        provider: "google"
      })

    {:ok, editor_user} = User.update_role(editor_user, :editor)

    {:ok,
     admin: admin_user,
     viewer: viewer_user,
     editor: editor_user}
  end

  defp as_user(conn, user) do
    assign(conn, :current_user, user)
  end

  describe "GET /api/v1/system/users" do
    test "admin can list all users", %{conn: conn, admin: admin} do
      conn =
        conn
        |> as_user(admin)
        |> get(~p"/api/v1/system/users")

      response = json_response(conn, 200)
      assert response["count"] >= 3
      assert is_list(response["items"])
    end

    test "viewer cannot list users", %{conn: conn, viewer: viewer} do
      conn =
        conn
        |> as_user(viewer)
        |> get(~p"/api/v1/system/users")

      assert json_response(conn, 403)
    end

    test "editor cannot list users", %{conn: conn, editor: editor} do
      conn =
        conn
        |> as_user(editor)
        |> get(~p"/api/v1/system/users")

      assert json_response(conn, 403)
    end

    test "unauthenticated request returns 401", %{conn: conn} do
      conn =
        conn
        |> put_req_header("accept", "application/json")
        |> get(~p"/api/v1/system/users")

      assert json_response(conn, 401)
    end
  end

  describe "GET /api/v1/system/users/:id" do
    test "admin can get a specific user", %{conn: conn, admin: admin, viewer: viewer} do
      id = "#{viewer.provider}:#{viewer.sub}"

      conn =
        conn
        |> as_user(admin)
        |> get(~p"/api/v1/system/users/#{id}")

      response = json_response(conn, 200)
      assert response["count"] == 1
      assert [user] = response["items"]
      assert user["email"] == "viewer@example.com"
      assert user["role"] == "viewer"
    end

    test "viewer can show a user (read-only)", %{conn: conn, viewer: viewer, admin: admin} do
      id = "#{admin.provider}:#{admin.sub}"

      conn =
        conn
        |> as_user(viewer)
        |> get(~p"/api/v1/system/users/#{id}")

      response = json_response(conn, 200)
      assert response["count"] == 1
    end

    test "returns 404 for nonexistent user", %{conn: conn, admin: admin} do
      conn =
        conn
        |> as_user(admin)
        |> get(~p"/api/v1/system/users/google:nonexistent")

      assert json_response(conn, 404)
    end

    test "returns 404 for invalid id format", %{conn: conn, admin: admin} do
      conn =
        conn
        |> as_user(admin)
        |> get(~p"/api/v1/system/users/invalidformat")

      assert json_response(conn, 404)
    end
  end

  describe "PATCH /api/v1/system/users/:id" do
    test "admin can update user role", %{conn: conn, admin: admin, viewer: viewer} do
      id = "#{viewer.provider}:#{viewer.sub}"

      conn =
        conn
        |> as_user(admin)
        |> patch(~p"/api/v1/system/users/#{id}", %{"role" => "editor"})

      response = json_response(conn, 200)
      assert [user] = response["items"]
      assert user["role"] == "editor"
    end

    test "returns 422 for invalid role", %{conn: conn, admin: admin, viewer: viewer} do
      id = "#{viewer.provider}:#{viewer.sub}"

      conn =
        conn
        |> as_user(admin)
        |> patch(~p"/api/v1/system/users/#{id}", %{"role" => "superadmin"})

      response = json_response(conn, 422)
      assert response["error"] == "validation_error"
    end

    test "viewer cannot update user role", %{conn: conn, viewer: viewer, editor: editor} do
      id = "#{editor.provider}:#{editor.sub}"

      conn =
        conn
        |> as_user(viewer)
        |> patch(~p"/api/v1/system/users/#{id}", %{"role" => "viewer"})

      assert json_response(conn, 403)
    end

    test "returns 404 for nonexistent user", %{conn: conn, admin: admin} do
      conn =
        conn
        |> as_user(admin)
        |> patch(~p"/api/v1/system/users/google:nonexistent", %{"role" => "editor"})

      assert json_response(conn, 404)
    end
  end

  describe "DELETE /api/v1/system/users/:id" do
    test "admin can disable a user", %{conn: conn, admin: admin, viewer: viewer} do
      id = "#{viewer.provider}:#{viewer.sub}"

      conn =
        conn
        |> as_user(admin)
        |> delete(~p"/api/v1/system/users/#{id}")

      response = json_response(conn, 200)
      assert [user] = response["items"]
      assert user["disabled"] == true
    end

    test "viewer cannot disable a user", %{conn: conn, viewer: viewer, editor: editor} do
      id = "#{editor.provider}:#{editor.sub}"

      conn =
        conn
        |> as_user(viewer)
        |> delete(~p"/api/v1/system/users/#{id}")

      assert json_response(conn, 403)
    end

    test "returns 404 for nonexistent user", %{conn: conn, admin: admin} do
      conn =
        conn
        |> as_user(admin)
        |> delete(~p"/api/v1/system/users/google:nonexistent")

      assert json_response(conn, 404)
    end
  end

  defp clean_items do
    for {expr, vals} <- [
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
