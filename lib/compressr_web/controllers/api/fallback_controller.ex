defmodule CompressrWeb.Api.FallbackController do
  @moduledoc """
  Translates controller action results into valid `Plug.Conn` responses.
  """

  use CompressrWeb, :controller

  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(404)
    |> json(%{error: "not_found"})
  end

  def call(conn, {:error, {:missing_fields, fields}}) do
    conn
    |> put_status(422)
    |> json(%{error: "validation_error", details: %{missing_fields: fields}})
  end

  def call(conn, {:error, :unknown_type}) do
    conn
    |> put_status(422)
    |> json(%{error: "validation_error", details: %{message: "unknown type"}})
  end

  def call(conn, {:error, reason}) when is_binary(reason) do
    conn
    |> put_status(422)
    |> json(%{error: "validation_error", details: %{message: reason}})
  end

  def call(conn, {:error, _reason}) do
    conn
    |> put_status(500)
    |> json(%{error: "internal_server_error"})
  end
end
