defmodule Compressr.Auth.ApiTokenTest do
  use ExUnit.Case, async: false

  alias Compressr.Auth.{ApiToken, User}

  setup do
    clean_tokens()
    clean_users()

    # Create a test user
    {:ok, user} =
      User.find_or_create(%{
        sub: "token-test-user",
        email: "tokenuser@example.com",
        display_name: "Token User",
        provider: "google"
      })

    {:ok, user: user}
  end

  describe "create/1" do
    test "returns a raw token with cpr_ prefix", %{user: user} do
      {:ok, raw_token} = ApiToken.create(user)
      assert String.starts_with?(raw_token, "cpr_")
    end

    test "raw token is not stored in DynamoDB (only the hash)", %{user: user} do
      {:ok, raw_token} = ApiToken.create(user)

      # Scan for all api_token items
      result =
        ExAws.Dynamo.scan("compressr_test_config",
          filter_expression: "pk = :pk",
          expression_attribute_values: [pk: "api_token"]
        )
        |> ExAws.request!()

      items = Map.get(result, "Items", [])

      # Verify no item contains the raw token as sk
      sks = Enum.map(items, fn item -> get_in(item, ["sk", "S"]) end)
      refute raw_token in sks

      # The sk should be the SHA-256 hash of the raw token
      expected_hash =
        :crypto.hash(:sha256, raw_token) |> Base.encode16(case: :lower)

      assert expected_hash in sks
    end
  end

  describe "verify/1" do
    test "verifies a valid token and returns the user", %{user: user} do
      {:ok, raw_token} = ApiToken.create(user)

      assert {:ok, verified_user} = ApiToken.verify(raw_token)
      assert verified_user.sub == user.sub
      assert verified_user.email == user.email
      assert verified_user.provider == user.provider
    end

    test "rejects an invalid token" do
      assert {:error, :invalid_token} = ApiToken.verify("cpr_invalid_token_here")
    end

    test "rejects a random string" do
      assert {:error, :invalid_token} = ApiToken.verify("not_even_a_token")
    end
  end

  describe "revoke/1" do
    test "revokes a token so it can no longer be verified", %{user: user} do
      {:ok, raw_token} = ApiToken.create(user)

      # Token works before revocation
      assert {:ok, _} = ApiToken.verify(raw_token)

      # Revoke
      assert :ok = ApiToken.revoke(raw_token)

      # Token no longer works
      assert {:error, :invalid_token} = ApiToken.verify(raw_token)
    end
  end

  describe "list_for_user/1" do
    test "lists tokens for a user (metadata only)", %{user: user} do
      {:ok, _} = ApiToken.create(user)
      {:ok, _} = ApiToken.create(user)

      {:ok, tokens} = ApiToken.list_for_user(user)
      assert length(tokens) == 2

      Enum.each(tokens, fn token ->
        assert token.user_sub == user.sub
        assert token.user_provider == user.provider
        assert token.created_at != nil
        # Ensure no hash is exposed
        refute Map.has_key?(token, :sk)
        refute Map.has_key?(token, :token_hash)
      end)
    end

    test "returns empty list for user with no tokens" do
      other_user = %User{
        sub: "no-tokens-user",
        email: "notokens@example.com",
        provider: "google",
        role: :viewer
      }

      {:ok, tokens} = ApiToken.list_for_user(other_user)
      assert tokens == []
    end
  end

  defp clean_tokens do
    result =
      ExAws.Dynamo.scan("compressr_test_config",
        filter_expression: "pk = :pk",
        expression_attribute_values: [pk: "api_token"]
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

  defp clean_users do
    result =
      ExAws.Dynamo.scan("compressr_test_config",
        filter_expression: "begins_with(pk, :prefix)",
        expression_attribute_values: [prefix: "user#"]
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
