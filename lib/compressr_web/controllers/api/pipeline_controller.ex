defmodule CompressrWeb.Api.PipelineController do
  use CompressrWeb, :controller

  alias Compressr.Pipeline.Config

  action_fallback CompressrWeb.Api.FallbackController

  def index(conn, _params) do
    case Config.list() do
      {:ok, pipelines} ->
        conn
        |> put_status(200)
        |> json(%{items: pipelines, count: length(pipelines)})

      {:error, _} = error ->
        error
    end
  end

  def show(conn, %{"id" => id}) do
    case Config.get(id) do
      {:ok, nil} ->
        {:error, :not_found}

      {:ok, pipeline} ->
        conn
        |> put_status(200)
        |> json(%{items: [pipeline], count: 1})

      {:error, _} = error ->
        error
    end
  end

  def create(conn, params) do
    id = params["id"] || generate_id()
    config = Map.put(params, "id", id)

    case Config.save(config) do
      {:ok, saved} ->
        conn
        |> put_status(201)
        |> json(%{items: [saved], count: 1})

      {:error, _} = error ->
        error
    end
  end

  def update(conn, %{"id" => id} = params) do
    case Config.get(id) do
      {:ok, nil} ->
        {:error, :not_found}

      {:ok, existing} ->
        merged =
          existing
          |> Map.merge(Map.drop(params, ["id"]))
          |> Map.put("id", id)

        case Config.save(merged) do
          {:ok, updated} ->
            conn
            |> put_status(200)
            |> json(%{items: [updated], count: 1})

          {:error, _} = error ->
            error
        end

      {:error, _} = error ->
        error
    end
  end

  def delete(conn, %{"id" => id}) do
    case Config.get(id) do
      {:ok, nil} ->
        {:error, :not_found}

      {:ok, _pipeline} ->
        :ok = Config.delete(id)

        conn
        |> put_status(200)
        |> json(%{items: [], count: 0})

      {:error, _} = error ->
        error
    end
  end

  defp generate_id do
    Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
  end
end
