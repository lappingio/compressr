defmodule CompressrWeb.Api.TokenController do
  use CompressrWeb, :controller

  alias Compressr.Auth.ApiToken

  action_fallback CompressrWeb.Api.FallbackController

  def create(conn, params) do
    user = conn.assigns[:current_user]

    if user do
      case ApiToken.create(user) do
        {:ok, raw_token} ->
          conn
          |> put_status(201)
          |> json(%{
            items: [
              %{
                token: raw_token,
                label: params["label"],
                created_at: DateTime.utc_now() |> DateTime.to_iso8601()
              }
            ],
            count: 1
          })
      end
    else
      conn
      |> put_status(401)
      |> json(%{error: "unauthorized"})
    end
  end

  def index(conn, _params) do
    user = conn.assigns[:current_user]

    if user do
      {:ok, tokens} = ApiToken.list_for_user(user)

      conn
      |> put_status(200)
      |> json(%{items: tokens, count: length(tokens)})
    else
      conn
      |> put_status(401)
      |> json(%{error: "unauthorized"})
    end
  end

  def delete(conn, %{"id" => id}) do
    # id here is the raw token or token identifier
    ApiToken.revoke(id)

    conn
    |> put_status(200)
    |> json(%{items: [], count: 0})
  end
end
