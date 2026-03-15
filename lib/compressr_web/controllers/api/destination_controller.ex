defmodule CompressrWeb.Api.DestinationController do
  use CompressrWeb, :controller

  alias Compressr.Destination.Config

  action_fallback CompressrWeb.Api.FallbackController

  def index(conn, _params) do
    case Config.list() do
      {:ok, destinations} ->
        items = Enum.map(destinations, &struct_to_map/1)

        conn
        |> put_status(200)
        |> json(%{items: items, count: length(items)})

      {:error, _} = error ->
        error
    end
  end

  def show(conn, %{"id" => id}) do
    case Config.get(id) do
      {:ok, nil} ->
        {:error, :not_found}

      {:ok, destination} ->
        conn
        |> put_status(200)
        |> json(%{items: [struct_to_map(destination)], count: 1})

      {:error, _} = error ->
        error
    end
  end

  def create(conn, params) do
    id = params["id"] || generate_id()

    dest = %Config{
      id: id,
      name: params["name"],
      type: params["type"],
      config: params["config"] || %{},
      enabled: Map.get(params, "enabled", true),
      post_processing_pipeline_id: params["post_processing_pipeline_id"],
      backpressure_mode: parse_backpressure_mode(params["backpressure_mode"])
    }

    case Config.save(dest) do
      {:ok, saved} ->
        conn
        |> put_status(201)
        |> json(%{items: [struct_to_map(saved)], count: 1})

      {:error, _} = error ->
        error
    end
  end

  def update(conn, %{"id" => id} = params) do
    case Config.get(id) do
      {:ok, nil} ->
        {:error, :not_found}

      {:ok, existing} ->
        updated = %Config{
          id: id,
          name: Map.get(params, "name", existing.name),
          type: Map.get(params, "type", existing.type),
          config: Map.get(params, "config", existing.config),
          enabled: Map.get(params, "enabled", existing.enabled),
          post_processing_pipeline_id:
            Map.get(params, "post_processing_pipeline_id", existing.post_processing_pipeline_id),
          backpressure_mode:
            parse_backpressure_mode(
              Map.get(params, "backpressure_mode", to_string(existing.backpressure_mode))
            ),
          inserted_at: existing.inserted_at
        }

        case Config.save(updated) do
          {:ok, saved} ->
            conn
            |> put_status(200)
            |> json(%{items: [struct_to_map(saved)], count: 1})

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

      {:ok, _dest} ->
        :ok = Config.delete(id)

        conn
        |> put_status(200)
        |> json(%{items: [], count: 0})

      {:error, _} = error ->
        error
    end
  end

  defp struct_to_map(%Config{} = dest) do
    %{
      "id" => dest.id,
      "name" => dest.name,
      "type" => dest.type,
      "config" => dest.config,
      "enabled" => dest.enabled,
      "post_processing_pipeline_id" => dest.post_processing_pipeline_id,
      "backpressure_mode" => to_string(dest.backpressure_mode),
      "inserted_at" => dest.inserted_at,
      "updated_at" => dest.updated_at
    }
  end

  defp parse_backpressure_mode("drop"), do: :drop
  defp parse_backpressure_mode("queue"), do: :queue
  defp parse_backpressure_mode(_), do: :block

  defp generate_id do
    Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
  end
end
