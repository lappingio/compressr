defmodule Compressr.Config.Cache do
  @moduledoc """
  Local file-based config cache for resilience against DynamoDB outages.

  On every successful config load from DynamoDB, the config is written to a
  local JSON file. When DynamoDB is unreachable at boot, the node can start
  with cached config from the last successful load.

  Cache location is configurable via `:compressr, :config_cache_dir`, defaulting
  to `data/config_cache.json` style paths under `data/`.
  """

  require Logger

  @valid_resource_types [:sources, :destinations, :pipelines, :routes]

  @doc """
  Write configs for a resource type to the local cache file.

  Returns `:ok` on success, `{:error, reason}` on failure.
  """
  @spec write_cache(atom(), list()) :: :ok | {:error, term()}
  def write_cache(resource_type, items) when resource_type in @valid_resource_types and is_list(items) do
    path = cache_path(resource_type)

    with :ok <- ensure_dir(path),
         {:ok, json} <- encode_items(items),
         :ok <- File.write(path, json) do
      Logger.debug("Config cache updated for #{resource_type} (#{length(items)} items)")
      :ok
    else
      {:error, reason} = err ->
        Logger.warning("Failed to write config cache for #{resource_type}: #{inspect(reason)}")
        err
    end
  end

  def write_cache(resource_type, _items) when resource_type not in @valid_resource_types do
    {:error, {:invalid_resource_type, resource_type}}
  end

  @doc """
  Read configs for a resource type from the local cache file.

  Returns `{:ok, items}` on success, `{:error, :not_found}` if the cache
  file does not exist, or `{:error, :corrupted}` if the cache cannot be decoded.
  """
  @spec read_cache(atom()) :: {:ok, list()} | {:error, :not_found | :corrupted}
  def read_cache(resource_type) when resource_type in @valid_resource_types do
    path = cache_path(resource_type)

    case File.read(path) do
      {:ok, data} ->
        case Jason.decode(data) do
          {:ok, items} when is_list(items) ->
            {:ok, items}

          {:ok, _not_a_list} ->
            Logger.warning("Config cache for #{resource_type} is corrupted (not a list)")
            {:error, :corrupted}

          {:error, _decode_error} ->
            Logger.warning("Config cache for #{resource_type} is corrupted (invalid JSON)")
            {:error, :corrupted}
        end

      {:error, :enoent} ->
        {:error, :not_found}

      {:error, reason} ->
        Logger.warning("Failed to read config cache for #{resource_type}: #{inspect(reason)}")
        {:error, :not_found}
    end
  end

  def read_cache(resource_type) do
    {:error, {:invalid_resource_type, resource_type}}
  end

  @doc """
  Returns the file path for a given resource type's cache file.
  """
  @spec cache_path(atom()) :: String.t()
  def cache_path(resource_type) do
    dir = cache_dir()
    Path.join(dir, "#{resource_type}.json")
  end

  # Private

  defp cache_dir do
    Application.get_env(:compressr, :config_cache_dir, "data")
  end

  defp ensure_dir(path) do
    path
    |> Path.dirname()
    |> File.mkdir_p()
  end

  defp encode_items(items) do
    case Jason.encode(items, pretty: true) do
      {:ok, json} -> {:ok, json}
      {:error, reason} -> {:error, {:encode_error, reason}}
    end
  end
end
