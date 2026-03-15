defmodule Compressr.Config.Loader do
  @moduledoc """
  Config loading with automatic fallback to local cache.

  Attempts to load configuration from DynamoDB first. If DynamoDB is
  unreachable, falls back to the local config cache (stale data). After
  a successful DynamoDB load, the cache is updated.
  """

  require Logger

  alias Compressr.Config.Cache

  @type resource_type :: :sources | :destinations | :pipelines | :routes

  @doc """
  Load configuration for a resource type.

  Tries DynamoDB first, falls back to cache on failure. After a successful
  DynamoDB load, updates the local cache.

  Returns `{:ok, items}` or `{:error, :no_config_available}`.
  """
  @spec load(resource_type()) :: {:ok, list()} | {:error, :no_config_available}
  def load(resource_type) do
    case load_from_dynamo(resource_type) do
      {:ok, items} ->
        # Update cache in the background — don't let cache write failure block config load
        Cache.write_cache(resource_type, items)
        {:ok, items}

      {:error, dynamo_reason} ->
        Logger.warning(
          "DynamoDB unreachable, loading #{resource_type} from local cache (stale data). " <>
            "DynamoDB error: #{inspect(dynamo_reason)}"
        )

        case Cache.read_cache(resource_type) do
          {:ok, items} ->
            Logger.info("Loaded #{length(items)} #{resource_type} from local cache")
            {:ok, items}

          {:error, cache_reason} ->
            Logger.error(
              "No config available for #{resource_type}. " <>
                "DynamoDB: #{inspect(dynamo_reason)}, Cache: #{inspect(cache_reason)}"
            )

            {:error, :no_config_available}
        end
    end
  end

  # Private

  defp load_from_dynamo(:sources) do
    Compressr.Source.Config.list()
  rescue
    e -> {:error, e}
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  defp load_from_dynamo(:destinations) do
    case Compressr.Destination.Config.list() do
      {:ok, configs} ->
        # Convert structs to maps for JSON serialization in cache
        items = Enum.map(configs, &destination_to_map/1)
        {:ok, items}

      {:error, _} = err ->
        err
    end
  rescue
    e -> {:error, e}
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  defp load_from_dynamo(resource_type) when resource_type in [:pipelines, :routes] do
    # Pipelines and routes config modules may not exist yet
    # Return empty list for now, will be wired up when those modules are implemented
    {:ok, []}
  rescue
    e -> {:error, e}
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  defp destination_to_map(%Compressr.Destination.Config{} = config) do
    %{
      "id" => config.id,
      "name" => config.name,
      "type" => config.type,
      "config" => config.config,
      "enabled" => config.enabled,
      "post_processing_pipeline_id" => config.post_processing_pipeline_id,
      "backpressure_mode" => to_string(config.backpressure_mode),
      "inserted_at" => config.inserted_at,
      "updated_at" => config.updated_at
    }
  end

  defp destination_to_map(map) when is_map(map), do: map
end
