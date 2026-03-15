defmodule Compressr.Source.Config do
  @moduledoc """
  CRUD operations for source configurations stored in DynamoDB.

  Source configs are stored in the config table with:
    pk = "source"
    sk = "\#{source_id}"
  """

  @required_fields ~w(id name type config)

  @doc """
  Save a source configuration to DynamoDB.

  Validates required fields and type-specific config before saving.
  """
  @spec save(map()) :: {:ok, map()} | {:error, term()}
  def save(source_config) when is_map(source_config) do
    with :ok <- validate_required(source_config),
         :ok <- validate_type(source_config) do
      now = DateTime.utc_now() |> DateTime.to_iso8601()

      config = Map.merge(
        %{
          "enabled" => true,
          "pre_processing_pipeline_id" => nil,
          "inserted_at" => now,
          "updated_at" => now
        },
        normalize_keys(source_config)
      )

      config = Map.put(config, "updated_at", now)

      item = %{
        "pk" => "source",
        "sk" => config["id"],
        "id" => config["id"],
        "name" => config["name"],
        "type" => config["type"],
        "config" => Jason.encode!(config["config"] || %{}),
        "enabled" => config["enabled"],
        "inserted_at" => config["inserted_at"],
        "updated_at" => config["updated_at"]
      }

      item =
        if config["pre_processing_pipeline_id"] do
          Map.put(item, "pre_processing_pipeline_id", config["pre_processing_pipeline_id"])
        else
          item
        end

      ExAws.Dynamo.put_item(table_name(), item)
      |> ExAws.request!()

      {:ok, config}
    end
  end

  @doc """
  Get a source configuration by ID.
  """
  @spec get(String.t()) :: {:ok, map() | nil}
  def get(source_id) when is_binary(source_id) do
    result =
      ExAws.Dynamo.get_item(table_name(), %{"pk" => "source", "sk" => source_id})
      |> ExAws.request!()

    case result do
      %{"Item" => item} when map_size(item) > 0 ->
        {:ok, item_to_config(item)}

      _ ->
        {:ok, nil}
    end
  end

  @doc """
  List all source configurations.
  """
  @spec list() :: {:ok, [map()]}
  def list do
    result =
      ExAws.Dynamo.query(table_name(),
        key_condition_expression: "pk = :pk",
        expression_attribute_values: [pk: "source"]
      )
      |> ExAws.request!()

    configs =
      result
      |> Map.get("Items", [])
      |> Enum.map(&item_to_config/1)

    {:ok, configs}
  end

  @doc """
  Delete a source configuration by ID.
  """
  @spec delete(String.t()) :: :ok
  def delete(source_id) when is_binary(source_id) do
    ExAws.Dynamo.delete_item(table_name(), %{"pk" => "source", "sk" => source_id})
    |> ExAws.request!()

    :ok
  end

  # --- Private ---

  defp validate_required(config) do
    config = normalize_keys(config)

    missing =
      Enum.filter(@required_fields, fn field ->
        val = Map.get(config, field)
        is_nil(val) or val == ""
      end)

    case missing do
      [] -> :ok
      fields -> {:error, {:missing_fields, fields}}
    end
  end

  defp validate_type(config) do
    config = normalize_keys(config)
    type = Map.get(config, "type")
    source_config = Map.get(config, "config", %{})

    Compressr.Source.validate_config_for_type(type, source_config)
  end

  defp normalize_keys(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
  end

  defp item_to_config(item) do
    %{
      "id" => get_s(item, "id"),
      "name" => get_s(item, "name"),
      "type" => get_s(item, "type"),
      "config" => decode_config(get_s(item, "config")),
      "enabled" => get_bool(item, "enabled"),
      "pre_processing_pipeline_id" => get_s(item, "pre_processing_pipeline_id"),
      "inserted_at" => get_s(item, "inserted_at"),
      "updated_at" => get_s(item, "updated_at")
    }
  end

  defp decode_config(nil), do: %{}

  defp decode_config(json) do
    case Jason.decode(json) do
      {:ok, map} -> map
      _ -> %{}
    end
  end

  defp get_s(item, key) do
    case Map.get(item, key) do
      %{"S" => val} -> val
      _ -> nil
    end
  end

  defp get_bool(item, key) do
    case Map.get(item, key) do
      %{"BOOL" => val} -> val
      _ -> false
    end
  end

  defp table_name do
    prefix = Application.get_env(:compressr, :dynamodb_table_prefix, "compressr_")
    "#{prefix}config"
  end
end
