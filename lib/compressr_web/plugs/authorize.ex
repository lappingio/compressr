defmodule CompressrWeb.Plugs.Authorize do
  @moduledoc """
  Plug that checks authorization after authentication.

  Uses the current_user from conn.assigns (set by RequireAuth) and checks
  if the user has permission to perform the requested action on the resource type
  using the RBAC module.

  ## Usage

      plug CompressrWeb.Plugs.Authorize, action: :create, resource: :source

  ## Options

    - `:action` — the action to authorize (e.g., :list, :show, :create, :update, :delete, :manage)
    - `:resource` — the resource type (e.g., :source, :destination, :pipeline, :route, :user)
  """

  import Plug.Conn

  alias Compressr.Auth.RBAC

  @behaviour Plug

  @impl true
  def init(opts) do
    action = Keyword.fetch!(opts, :action)
    resource = Keyword.fetch!(opts, :resource)
    %{action: action, resource: resource}
  end

  @impl true
  def call(conn, %{action: action, resource: resource}) do
    case conn.assigns[:current_user] do
      nil ->
        reject_unauthenticated(conn)

      user ->
        case RBAC.authorize(user, action, resource) do
          :ok ->
            conn

          {:error, :forbidden} ->
            reject_forbidden(conn)
        end
    end
  end

  defp reject_unauthenticated(conn) do
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

  defp reject_forbidden(conn) do
    if json_request?(conn) do
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(403, Jason.encode!(%{error: "forbidden"}))
      |> halt()
    else
      conn
      |> put_resp_content_type("text/html")
      |> send_resp(403, forbidden_html())
      |> halt()
    end
  end

  defp json_request?(conn) do
    case get_req_header(conn, "accept") do
      [accept] -> String.contains?(accept, "application/json")
      _ -> false
    end
  end

  defp forbidden_html do
    """
    <!DOCTYPE html>
    <html>
    <head><title>403 Forbidden</title></head>
    <body>
      <h1>403 Forbidden</h1>
      <p>You do not have permission to access this resource.</p>
    </body>
    </html>
    """
  end
end
