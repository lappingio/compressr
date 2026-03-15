defmodule CompressrWeb.Api.UserController do
  @moduledoc """
  User management API controller.

  All actions require admin role except show (which allows users to view themselves).
  """

  use CompressrWeb, :controller

  alias Compressr.Auth.User
  alias Compressr.Auth.RBAC

  plug :authorize_action

  action_fallback CompressrWeb.Api.FallbackController

  # Map controller actions to RBAC actions and authorize.
  # Relies on conn.assigns[:current_user] being set by the RequireAuth plug
  # in the router pipeline, or by Bearer token authentication.
  defp authorize_action(conn, _opts) do
    {rbac_action, resource} = action_permission(conn.private.phoenix_action)

    case conn.assigns[:current_user] do
      nil ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(401, Jason.encode!(%{error: "unauthorized"}))
        |> halt()

      user ->
        case RBAC.authorize(user, rbac_action, resource) do
          :ok -> conn
          {:error, :forbidden} ->
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(403, Jason.encode!(%{error: "forbidden"}))
            |> halt()
        end
    end
  end

  defp action_permission(:index), do: {:manage, :user}
  defp action_permission(:show), do: {:show, :user}
  defp action_permission(:update), do: {:manage, :user}
  defp action_permission(:delete), do: {:manage, :user}

  def index(conn, _params) do
    {:ok, users} = User.list_users()

    conn
    |> put_status(200)
    |> json(%{
      items: Enum.map(users, &serialize_user/1),
      count: length(users)
    })
  end

  def show(conn, %{"id" => id}) do
    # id is "provider:sub" format
    case parse_user_id(id) do
      {:ok, provider, sub} ->
        case User.get_by_provider_and_sub(provider, sub) do
          {:ok, nil} ->
            {:error, :not_found}

          {:ok, user} ->
            conn
            |> put_status(200)
            |> json(%{items: [serialize_user(user)], count: 1})
        end

      :error ->
        {:error, :not_found}
    end
  end

  def update(conn, %{"id" => id} = params) do
    case parse_user_id(id) do
      {:ok, provider, sub} ->
        case User.get_by_provider_and_sub(provider, sub) do
          {:ok, nil} ->
            {:error, :not_found}

          {:ok, user} ->
            new_role = params["role"]

            if new_role && new_role not in Enum.map(User.valid_roles(), &Atom.to_string/1) do
              conn
              |> put_status(422)
              |> json(%{
                error: "validation_error",
                details: %{
                  message: "invalid role",
                  valid_roles: Enum.map(User.valid_roles(), &Atom.to_string/1)
                }
              })
            else
              updated_user = if new_role do
                User.update_role(user, String.to_existing_atom(new_role))
              else
                {:ok, user}
              end

              {:ok, u} = updated_user

              conn
              |> put_status(200)
              |> json(%{items: [serialize_user(u)], count: 1})
            end
        end

      :error ->
        {:error, :not_found}
    end
  end

  def delete(conn, %{"id" => id}) do
    case parse_user_id(id) do
      {:ok, provider, sub} ->
        case User.get_by_provider_and_sub(provider, sub) do
          {:ok, nil} ->
            {:error, :not_found}

          {:ok, user} ->
            {:ok, disabled_user} = User.disable(user)

            conn
            |> put_status(200)
            |> json(%{items: [serialize_user(disabled_user)], count: 1})
        end

      :error ->
        {:error, :not_found}
    end
  end

  # User ID format: "provider:sub"
  defp parse_user_id(id) do
    case String.split(id, ":", parts: 2) do
      [provider, sub] when provider != "" and sub != "" ->
        {:ok, provider, sub}

      _ ->
        :error
    end
  end

  defp serialize_user(%User{} = user) do
    %{
      id: "#{user.provider}:#{user.sub}",
      sub: user.sub,
      email: user.email,
      display_name: user.display_name,
      provider: user.provider,
      role: Atom.to_string(user.role),
      disabled: Map.get(user, :disabled, false),
      inserted_at: user.inserted_at,
      updated_at: user.updated_at
    }
  end
end
