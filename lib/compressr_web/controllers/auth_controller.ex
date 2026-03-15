defmodule CompressrWeb.AuthController do
  use CompressrWeb, :controller

  @doc """
  Render the login page listing available OIDC providers.
  """
  def login(conn, _params) do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, login_html())
  end

  @doc """
  Handle OIDC callback. Placeholder for now.
  """
  def callback(conn, _params) do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, "<html><body><p>OIDC callback placeholder</p></body></html>")
  end

  @doc """
  Clear the session and redirect to the login page.
  """
  def logout(conn, _params) do
    conn
    |> configure_session(drop: true)
    |> redirect(to: "/auth/login")
  end

  defp login_html do
    """
    <!DOCTYPE html>
    <html>
    <head><title>Login - Compressr</title></head>
    <body>
      <h1>Login</h1>
      <p>Select a provider to sign in:</p>
      <ul>
        <li><a href="/auth/callback?provider=google">Google</a></li>
      </ul>
    </body>
    </html>
    """
  end
end
