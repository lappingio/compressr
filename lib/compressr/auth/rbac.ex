defmodule Compressr.Auth.RBAC do
  @moduledoc """
  Role-Based Access Control for Compressr.

  Defines permissions per role and provides authorization checks.

  Roles:
    - :admin  — full access (CRUD on all resources, manage users, view audit logs, manage providers)
    - :editor — CRUD on sources, destinations, pipelines, routes. Cannot manage users or providers.
    - :viewer — read-only access to all resources. Cannot create, update, or delete anything.
  """

  alias Compressr.Auth.User

  @type action :: :list | :show | :create | :update | :delete | :manage
  @type resource_type ::
          :source
          | :destination
          | :pipeline
          | :route
          | :user
          | :provider
          | :audit
          | :token
          | :cost

  @read_actions [:list, :show]
  @write_actions [:create, :update, :delete]

  # Resources that editors can manage (CRUD)
  @editor_resources [:source, :destination, :pipeline, :route]

  # All resource types
  @all_resources [:source, :destination, :pipeline, :route, :user, :provider, :audit, :token, :cost]

  @doc """
  Check if a user is authorized to perform an action on a resource type.

  Returns `:ok` if authorized, `{:error, :forbidden}` if not.

  ## Examples

      iex> admin = %User{role: :admin, sub: "1", email: "a@b.com", provider: "google"}
      iex> Compressr.Auth.RBAC.authorize(admin, :delete, :user)
      :ok

      iex> viewer = %User{role: :viewer, sub: "1", email: "a@b.com", provider: "google"}
      iex> Compressr.Auth.RBAC.authorize(viewer, :create, :source)
      {:error, :forbidden}
  """
  @spec authorize(User.t(), action(), resource_type()) :: :ok | {:error, :forbidden}
  def authorize(%User{role: role}, action, resource_type) do
    if permitted?(role, action, resource_type) do
      :ok
    else
      {:error, :forbidden}
    end
  end

  def authorize(nil, _action, _resource_type), do: {:error, :forbidden}
  def authorize(_user, _action, _resource_type), do: {:error, :forbidden}

  @doc """
  Returns true if the given role has permission for the action on the resource type.
  """
  @spec permitted?(atom(), action(), resource_type()) :: boolean()
  def permitted?(:admin, _action, _resource_type), do: true

  def permitted?(:editor, action, resource_type) when resource_type in @editor_resources do
    action in @read_actions ++ @write_actions ++ [:manage]
  end

  def permitted?(:editor, action, :token) do
    action in @read_actions ++ @write_actions
  end

  def permitted?(:editor, action, resource_type)
      when resource_type in @all_resources do
    action in @read_actions
  end

  def permitted?(:viewer, action, resource_type)
      when resource_type in @all_resources do
    action in @read_actions
  end

  def permitted?(_role, _action, _resource_type), do: false

  @doc """
  Returns all permissions for a given role as a list of {action, resource_type} tuples.
  Useful for introspection and debugging.
  """
  @spec permissions_for(atom()) :: [{action(), resource_type()}]
  def permissions_for(role) do
    actions = @read_actions ++ @write_actions ++ [:manage]

    for action <- actions,
        resource <- @all_resources,
        permitted?(role, action, resource) do
      {action, resource}
    end
  end
end
