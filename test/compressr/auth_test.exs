defmodule Compressr.AuthTest do
  use ExUnit.Case, async: false

  alias Compressr.Auth

  setup do
    # Clean up auth-related items between tests
    clean_items("user#")
    clean_items("api_token")
    :ok
  end

  describe "find_or_create_user/1" do
    test "creates a new user when one does not exist" do
      attrs = %{sub: "auth-test-sub-1", email: "test@example.com", provider: "google"}
      assert {:ok, user} = Auth.find_or_create_user(attrs)
      assert user.sub == "auth-test-sub-1"
      assert user.email == "test@example.com"
      assert user.provider == "google"
      assert user.role == :viewer
    end

    test "returns existing user on subsequent calls" do
      attrs = %{sub: "auth-test-sub-2", email: "test2@example.com", provider: "google"}
      {:ok, first} = Auth.find_or_create_user(attrs)
      {:ok, second} = Auth.find_or_create_user(attrs)
      assert first.sub == second.sub
    end
  end

  describe "get_user_by_provider_and_sub/2" do
    test "returns nil when user does not exist" do
      assert {:ok, nil} = Auth.get_user_by_provider_and_sub("google", "nonexistent-sub")
    end

    test "returns user when it exists" do
      attrs = %{sub: "auth-test-sub-3", email: "test3@example.com", provider: "google"}
      {:ok, _} = Auth.find_or_create_user(attrs)
      assert {:ok, user} = Auth.get_user_by_provider_and_sub("google", "auth-test-sub-3")
      assert user.email == "test3@example.com"
    end
  end

  describe "list_users/0" do
    test "returns empty list when no users exist" do
      assert {:ok, users} = Auth.list_users()
      assert is_list(users)
    end

    test "returns all users" do
      {:ok, _} = Auth.find_or_create_user(%{sub: "auth-list-1", email: "a@b.com", provider: "google"})
      {:ok, _} = Auth.find_or_create_user(%{sub: "auth-list-2", email: "c@d.com", provider: "google"})

      {:ok, users} = Auth.list_users()
      subs = Enum.map(users, & &1.sub)
      assert "auth-list-1" in subs
      assert "auth-list-2" in subs
    end
  end

  describe "create_api_token/1 and verify_api_token/1" do
    test "creates and verifies a token" do
      {:ok, user} = Auth.find_or_create_user(%{sub: "token-test-1", email: "t@t.com", provider: "google"})
      {:ok, raw_token} = Auth.create_api_token(user)

      assert is_binary(raw_token)
      assert String.starts_with?(raw_token, "cpr_")

      {:ok, verified_user} = Auth.verify_api_token(raw_token)
      assert verified_user.sub == "token-test-1"
    end

    test "verify returns error for invalid token" do
      assert {:error, :invalid_token} = Auth.verify_api_token("cpr_bogus_token")
    end
  end

  describe "revoke_api_token/1" do
    test "revokes a token so it can no longer be verified" do
      {:ok, user} = Auth.find_or_create_user(%{sub: "revoke-test-1", email: "r@r.com", provider: "google"})
      {:ok, raw_token} = Auth.create_api_token(user)

      :ok = Auth.revoke_api_token(raw_token)

      assert {:error, :invalid_token} = Auth.verify_api_token(raw_token)
    end
  end

  describe "list_api_tokens_for_user/1" do
    test "returns tokens for a user" do
      {:ok, user} = Auth.find_or_create_user(%{sub: "list-tok-1", email: "l@l.com", provider: "google"})
      {:ok, _} = Auth.create_api_token(user)
      {:ok, _} = Auth.create_api_token(user)

      {:ok, tokens} = Auth.list_api_tokens_for_user(user)
      assert length(tokens) >= 2
    end
  end

  defp clean_items(prefix) do
    result =
      ExAws.Dynamo.scan("compressr_test_config",
        filter_expression: "begins_with(pk, :prefix)",
        expression_attribute_values: [prefix: prefix]
      )
      |> ExAws.request!()

    items = Map.get(result, "Items", [])

    Enum.each(items, fn item ->
      pk = get_in(item, ["pk", "S"])
      sk = get_in(item, ["sk", "S"])

      if pk && sk do
        ExAws.Dynamo.delete_item("compressr_test_config", %{"pk" => pk, "sk" => sk})
        |> ExAws.request!()
      end
    end)
  end
end
