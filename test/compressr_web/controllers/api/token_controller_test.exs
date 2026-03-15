defmodule CompressrWeb.Api.TokenControllerTest do
  use CompressrWeb.ConnCase, async: false

  alias Compressr.Auth.ApiToken

  setup do
    clean_items("api_token")
    :ok
  end

  describe "POST /api/v1/auth/tokens" do
    test "creates a token for an authenticated user", %{conn: conn} do
      conn =
        conn
        |> assign_test_user()
        |> post(~p"/api/v1/auth/tokens", %{"label" => "test-token"})

      response = json_response(conn, 201)
      assert response["count"] == 1
      assert [item] = response["items"]
      assert is_binary(item["token"])
      assert String.starts_with?(item["token"], "cpr_")
      assert item["label"] == "test-token"
    end

    test "returns 401 for unauthenticated user", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/auth/tokens", %{"label" => "test"})

      assert %{"error" => "unauthorized"} = json_response(conn, 401)
    end
  end

  describe "GET /api/v1/auth/tokens" do
    test "lists tokens for the current user", %{conn: conn} do
      user = test_user()
      {:ok, _} = ApiToken.create(user)
      {:ok, _} = ApiToken.create(user)

      conn =
        conn
        |> assign_test_user()
        |> get(~p"/api/v1/auth/tokens")

      response = json_response(conn, 200)
      assert response["count"] == 2
      assert length(response["items"]) == 2
    end

    test "returns empty list when no tokens exist", %{conn: conn} do
      conn =
        conn
        |> assign_test_user()
        |> get(~p"/api/v1/auth/tokens")

      response = json_response(conn, 200)
      assert response["count"] == 0
      assert response["items"] == []
    end

    test "returns 401 for unauthenticated user", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/auth/tokens")

      assert %{"error" => "unauthorized"} = json_response(conn, 401)
    end
  end

  describe "DELETE /api/v1/auth/tokens/:id" do
    test "revokes a token", %{conn: conn} do
      user = test_user()
      {:ok, raw_token} = ApiToken.create(user)

      conn = delete(conn, "/api/v1/auth/tokens/#{URI.encode_www_form(raw_token)}")

      assert %{"items" => [], "count" => 0} = json_response(conn, 200)

      # Verify token is invalid now
      assert {:error, :invalid_token} = ApiToken.verify(raw_token)
    end
  end

  # --- Helpers ---

  defp test_user do
    %Compressr.Auth.User{
      sub: "test-sub-token",
      email: "test@example.com",
      provider: "test",
      role: :admin
    }
  end

  defp assign_test_user(conn) do
    assign(conn, :current_user, test_user())
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
