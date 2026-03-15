defmodule Compressr.Auth.UserTest do
  use ExUnit.Case, async: false

  alias Compressr.Auth.User

  setup do
    # Clean up any user items in the config table before each test
    clean_users()
    :ok
  end

  describe "find_or_create/1" do
    test "creates a new user on first login" do
      attrs = %{
        sub: "google-123",
        email: "test@example.com",
        display_name: "Test User",
        provider: "google"
      }

      assert {:ok, user} = User.find_or_create(attrs)
      assert user.sub == "google-123"
      assert user.email == "test@example.com"
      assert user.display_name == "Test User"
      assert user.provider == "google"
      assert user.role == :viewer
      assert user.inserted_at != nil
      assert user.updated_at != nil
    end

    test "updates an existing user on subsequent login" do
      attrs = %{
        sub: "google-456",
        email: "old@example.com",
        display_name: "Old Name",
        provider: "google"
      }

      {:ok, original} = User.find_or_create(attrs)

      updated_attrs = %{
        sub: "google-456",
        email: "new@example.com",
        display_name: "New Name",
        provider: "google"
      }

      {:ok, updated} = User.find_or_create(updated_attrs)

      assert updated.email == "new@example.com"
      assert updated.display_name == "New Name"
      assert updated.role == original.role
      assert updated.inserted_at == original.inserted_at
      assert updated.updated_at >= original.updated_at
    end
  end

  describe "get_by_provider_and_sub/2" do
    test "returns nil when user does not exist" do
      assert {:ok, nil} = User.get_by_provider_and_sub("google", "nonexistent")
    end

    test "returns user when found" do
      attrs = %{
        sub: "google-789",
        email: "found@example.com",
        display_name: "Found User",
        provider: "google"
      }

      {:ok, _} = User.find_or_create(attrs)

      assert {:ok, user} = User.get_by_provider_and_sub("google", "google-789")
      assert user.email == "found@example.com"
      assert user.provider == "google"
    end
  end

  describe "list_users/0" do
    test "returns empty list when no users" do
      assert {:ok, []} = User.list_users()
    end

    test "returns all users" do
      {:ok, _} =
        User.find_or_create(%{
          sub: "user-1",
          email: "one@example.com",
          display_name: "One",
          provider: "google"
        })

      {:ok, _} =
        User.find_or_create(%{
          sub: "user-2",
          email: "two@example.com",
          display_name: "Two",
          provider: "github"
        })

      {:ok, users} = User.list_users()
      assert length(users) == 2

      emails = Enum.map(users, & &1.email) |> Enum.sort()
      assert emails == ["one@example.com", "two@example.com"]
    end
  end

  defp clean_users do
    # Scan for all user items and delete them
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
