defmodule CompressrWeb.Plugs.RequireAuth do
  @moduledoc """
  Plug for route protection.

  Checks session for a user, or the Authorization header for a Bearer token.
  On success, sets `conn.assigns.current_user`.
  On failure, returns 401 for JSON requests or redirects to /auth/login for HTML.
  """

  import Plug.Conn
  alias Compressr.Auth.ApiToken

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    cond do
      # Check session-based auth
      user = conn.assigns[:current_user] ->
        # Already assigned by upstream plug
        assign(conn, :current_user, user)

      user_data = get_session(conn, :current_user) ->
        user = deserialize_user(user_data)
        assign(conn, :current_user, user)

      # Check Bearer token
      token = extract_bearer_token(conn) ->
        case ApiToken.verify(token) do
          {:ok, user} ->
            assign(conn, :current_user, user)

          {:error, :invalid_token} ->
            reject(conn)
        end

      true ->
        reject(conn)
    end
  end

  defp extract_bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> String.trim(token)
      _ -> nil
    end
  end

  defp reject(conn) do
    if json_request?(conn) do
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(401, Jason.encode!(%{error: "unauthorized"}))
      |> halt()
    else
      conn
      |> Phoenix.Controller.redirect(to: "/auth/login")
      |> halt()
    end
  end

  defp json_request?(conn) do
    case get_req_header(conn, "accept") do
      [accept] -> String.contains?(accept, "application/json")
      _ -> false
    end
  end

  defp deserialize_user(user_data) when is_map(user_data) do
    %Compressr.Auth.User{
      sub: user_data["sub"] || user_data[:sub],
      email: user_data["email"] || user_data[:email],
      display_name: user_data["display_name"] || user_data[:display_name],
      provider: user_data["provider"] || user_data[:provider],
      role:
        (user_data["role"] || user_data[:role] || "viewer")
        |> to_string()
        |> String.to_existing_atom(),
      disabled: (user_data["disabled"] || user_data[:disabled]) == true,
      inserted_at: user_data["inserted_at"] || user_data[:inserted_at],
      updated_at: user_data["updated_at"] || user_data[:updated_at]
    }
  end
end
