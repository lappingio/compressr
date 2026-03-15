defmodule Compressr.Auth.User do
  @moduledoc """
  User management backed by DynamoDB.

  Users are stored in the config table with:
    pk = "user#\#{provider}"
    sk = "\#{sub}"
  """

  @enforce_keys [:sub, :email, :provider, :role]
  defstruct [:sub, :email, :display_name, :provider, :role, :inserted_at, :updated_at]

  @type t :: %__MODULE__{
          sub: String.t(),
          email: String.t(),
          display_name: String.t() | nil,
          provider: String.t(),
          role: :admin | :viewer,
          inserted_at: String.t() | nil,
          updated_at: String.t() | nil
        }

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
