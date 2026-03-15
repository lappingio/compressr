defmodule Compressr.Auth.RBACTest do
  use ExUnit.Case, async: true

  alias Compressr.Auth.RBAC
  alias Compressr.Auth.User

  defp build_user(role) do
    %User{
      sub: "test-sub",
      email: "test@example.com",
      provider: "google",
      role: role,
      display_name: "Test User"
    }
  end

  describe "admin role" do
    setup do
      {:ok, user: build_user(:admin)}
    end

    test "can perform all actions on all resource types", %{user: user} do
      for action <- [:list, :show, :create, :update, :delete, :manage],
          resource <- [:source, :destination, :pipeline, :route, :user, :provider, :audit, :token, :cost] do
        assert :ok == RBAC.authorize(user, action, resource),
               "admin should be able to #{action} #{resource}"
      end
    end
  end

  describe "editor role" do
    setup do
      {:ok, user: build_user(:editor)}
    end

    test "can CRUD sources, destinations, pipelines, routes", %{user: user} do
      for action <- [:list, :show, :create, :update, :delete],
          resource <- [:source, :destination, :pipeline, :route] do
        assert :ok == RBAC.authorize(user, action, resource),
               "editor should be able to #{action} #{resource}"
      end
    end

    test "can manage sources, destinations, pipelines, routes", %{user: user} do
      for resource <- [:source, :destination, :pipeline, :route] do
        assert :ok == RBAC.authorize(user, :manage, resource)
      end
    end

    test "can read-only users, providers, audit, cost", %{user: user} do
      for resource <- [:user, :provider, :audit, :cost] do
        assert :ok == RBAC.authorize(user, :list, resource),
               "editor should be able to list #{resource}"
        assert :ok == RBAC.authorize(user, :show, resource),
               "editor should be able to show #{resource}"
      end
    end

    test "cannot create, update, delete, manage users", %{user: user} do
      for action <- [:create, :update, :delete, :manage] do
        assert {:error, :forbidden} == RBAC.authorize(user, action, :user),
               "editor should not be able to #{action} user"
      end
    end

    test "cannot create, update, delete, manage providers", %{user: user} do
      for action <- [:create, :update, :delete, :manage] do
        assert {:error, :forbidden} == RBAC.authorize(user, action, :provider),
               "editor should not be able to #{action} provider"
      end
    end

    test "can CRUD tokens", %{user: user} do
      for action <- [:list, :show, :create, :update, :delete] do
        assert :ok == RBAC.authorize(user, action, :token),
               "editor should be able to #{action} token"
      end
    end
  end

  describe "viewer role" do
    setup do
      {:ok, user: build_user(:viewer)}
    end

    test "can list and show all resources", %{user: user} do
      for resource <- [:source, :destination, :pipeline, :route, :user, :provider, :audit, :token, :cost] do
        assert :ok == RBAC.authorize(user, :list, resource),
               "viewer should be able to list #{resource}"
        assert :ok == RBAC.authorize(user, :show, resource),
               "viewer should be able to show #{resource}"
      end
    end

    test "cannot create any resources", %{user: user} do
      for resource <- [:source, :destination, :pipeline, :route, :user, :provider, :token] do
        assert {:error, :forbidden} == RBAC.authorize(user, :create, resource),
               "viewer should not be able to create #{resource}"
      end
    end

    test "cannot update any resources", %{user: user} do
      for resource <- [:source, :destination, :pipeline, :route, :user, :provider, :token] do
        assert {:error, :forbidden} == RBAC.authorize(user, :update, resource),
               "viewer should not be able to update #{resource}"
      end
    end

    test "cannot delete any resources", %{user: user} do
      for resource <- [:source, :destination, :pipeline, :route, :user, :provider, :token] do
        assert {:error, :forbidden} == RBAC.authorize(user, :delete, resource),
               "viewer should not be able to delete #{resource}"
      end
    end

    test "cannot manage any resources", %{user: user} do
      for resource <- [:source, :destination, :pipeline, :route, :user, :provider, :token] do
        assert {:error, :forbidden} == RBAC.authorize(user, :manage, resource),
               "viewer should not be able to manage #{resource}"
      end
    end
  end

  describe "unknown/invalid role" do
    test "unknown role is denied for all actions" do
      user = %User{
        sub: "test-sub",
        email: "test@example.com",
        provider: "google",
        role: :unknown,
        display_name: "Test User"
      }

      for action <- [:list, :show, :create, :update, :delete, :manage],
          resource <- [:source, :destination, :pipeline, :route, :user] do
        assert {:error, :forbidden} == RBAC.authorize(user, action, resource),
               "unknown role should be denied #{action} on #{resource}"
      end
    end

    test "nil user is denied" do
      assert {:error, :forbidden} == RBAC.authorize(nil, :list, :source)
    end
  end

  describe "permitted?/3" do
    test "returns boolean" do
      assert RBAC.permitted?(:admin, :delete, :user) == true
      assert RBAC.permitted?(:viewer, :delete, :user) == false
    end
  end

  describe "permissions_for/1" do
    test "admin has permissions on all resources" do
      perms = RBAC.permissions_for(:admin)
      assert {:delete, :user} in perms
      assert {:manage, :provider} in perms
      assert {:create, :source} in perms
    end

    test "viewer only has read permissions" do
      perms = RBAC.permissions_for(:viewer)
      assert {:list, :source} in perms
      assert {:show, :user} in perms
      refute {:create, :source} in perms
      refute {:delete, :user} in perms
    end

    test "editor has CRUD on editor resources but read-only on admin resources" do
      perms = RBAC.permissions_for(:editor)
      assert {:create, :source} in perms
      assert {:delete, :pipeline} in perms
      assert {:list, :user} in perms
      refute {:delete, :user} in perms
      refute {:manage, :provider} in perms
    end
  end
end
