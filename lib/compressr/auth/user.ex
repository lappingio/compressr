defmodule Compressr.Auth.User do
  @moduledoc """
  User management backed by DynamoDB.

  Users are stored in the config table with:
    pk = "user#\#{provider}"
    sk = "\#{sub}"
  """

  @enforce_keys [:sub, :email, :provider, :role]
  defstruct [:sub, :email, :display_name, :provider, :role, :disabled, :inserted_at, :updated_at]

  @type t :: %__MODULE__{
          sub: String.t(),
          email: String.t(),
          display_name: String.t() | nil,
          provider: String.t(),
          role: :admin | :editor | :viewer,
          disabled: boolean() | nil,
          inserted_at: String.t() | nil,
          updated_at: String.t() | nil
        }

  @valid_roles [:admin, :editor, :viewer]

  @doc "Returns the list of valid roles."
  @spec valid_roles() :: [:admin | :editor | :viewer]
  def valid_roles, do: @valid_roles

  @doc "Returns true if the user has the :admin role."
  @spec admin?(t()) :: boolean()
  def admin?(%__MODULE__{role: :admin}), do: true
  def admin?(_), do: false

  @doc "Returns true if the user has the :editor role."
  @spec editor?(t()) :: boolean()
  def editor?(%__MODULE__{role: :editor}), do: true
  def editor?(_), do: false

  @doc "Returns true if the user has the :viewer role."
  @spec viewer?(t()) :: boolean()
  def viewer?(%__MODULE__{role: :viewer}), do: true
  def viewer?(_), do: false

  @doc """
  Find an existing user or create a new one.

  Accepts a map with keys: :sub, :email, :display_name, :provider.
  On first login, creates the user with :viewer role.
  On subsequent logins, updates email and display_name.
  """
  @spec find_or_create(map()) :: {:ok, t()}
  def find_or_create(%{sub: sub, provider: provider} = attrs) do
    case get_by_provider_and_sub(provider, sub) do
      {:ok, nil} ->
        now = DateTime.utc_now() |> DateTime.to_iso8601()

        user = %__MODULE__{
          sub: sub,
          email: Map.get(attrs, :email, ""),
          display_name: Map.get(attrs, :display_name),
          provider: provider,
          role: :viewer,
          disabled: false,
          inserted_at: now,
          updated_at: now
        }

        item = user_to_dynamo_item(user)

        ExAws.Dynamo.put_item(table_name(), item)
        |> ExAws.request!()

        {:ok, user}

      {:ok, existing} ->
        now = DateTime.utc_now() |> DateTime.to_iso8601()

        updated = %{
          existing
          | email: Map.get(attrs, :email, existing.email),
            display_name: Map.get(attrs, :display_name, existing.display_name),
            updated_at: now
        }

        item = user_to_dynamo_item(updated)

        ExAws.Dynamo.put_item(table_name(), item)
        |> ExAws.request!()

        {:ok, updated}
    end
  end

  @doc """
  Get a user by provider and subject identifier.
  """
  @spec get_by_provider_and_sub(String.t(), String.t()) :: {:ok, t() | nil}
  def get_by_provider_and_sub(provider, sub) do
    result =
      ExAws.Dynamo.get_item(table_name(), %{"pk" => "user##{provider}", "sk" => sub})
      |> ExAws.request!()

    case result do
      %{"Item" => item} when map_size(item) > 0 ->
        {:ok, dynamo_item_to_user(item)}

      _ ->
        {:ok, nil}
    end
  end

  @doc """
  List all users.
  """
  @spec list_users() :: {:ok, [t()]}
  def list_users do
    result =
      ExAws.Dynamo.scan(table_name(),
        filter_expression: "begins_with(pk, :prefix)",
        expression_attribute_values: [prefix: "user#"]
      )
      |> ExAws.request!()

    users =
      result
      |> Map.get("Items", [])
      |> Enum.map(&dynamo_item_to_user/1)

    {:ok, users}
  end

  @doc """
  Update a user's role.
  """
  @spec update_role(t(), atom()) :: {:ok, t()}
  def update_role(%__MODULE__{} = user, new_role) when new_role in @valid_roles do
    now = DateTime.utc_now() |> DateTime.to_iso8601()
    updated = %{user | role: new_role, updated_at: now}
    item = user_to_dynamo_item(updated)

    ExAws.Dynamo.put_item(table_name(), item)
    |> ExAws.request!()

    {:ok, updated}
  end

  @doc """
  Disable a user by setting disabled: true.
  """
  @spec disable(t()) :: {:ok, t()}
  def disable(%__MODULE__{} = user) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()
    disabled_user = %{user | disabled: true, updated_at: now}
    item = user_to_dynamo_item(disabled_user)

    ExAws.Dynamo.put_item(table_name(), item)
    |> ExAws.request!()

    {:ok, disabled_user}
  end

  defp table_name do
    prefix = Application.get_env(:compressr, :dynamodb_table_prefix, "compressr_")
    "#{prefix}config"
  end

  defp user_to_dynamo_item(%__MODULE__{} = user) do
    %{
      "pk" => "user##{user.provider}",
      "sk" => user.sub,
      "email" => user.email || "",
      "display_name" => user.display_name || "",
      "provider" => user.provider,
      "role" => Atom.to_string(user.role),
      "disabled" => if(user.disabled, do: "true", else: "false"),
      "inserted_at" => user.inserted_at || "",
      "updated_at" => user.updated_at || ""
    }
  end

  defp dynamo_item_to_user(item) do
    %__MODULE__{
      sub: get_s(item, "sk"),
      email: get_s(item, "email"),
      display_name: get_s(item, "display_name"),
      provider: get_s(item, "provider"),
      role: item |> get_s("role") |> String.to_existing_atom(),
      disabled: get_s(item, "disabled") == "true",
      inserted_at: get_s(item, "inserted_at"),
      updated_at: get_s(item, "updated_at")
    }
  end

  defp get_s(item, key) do
    case Map.get(item, key) do
      %{"S" => val} -> val
      _ -> nil
    end
  end
end
