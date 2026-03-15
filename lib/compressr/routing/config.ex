defmodule Compressr.Routing.Config do
  @moduledoc """
  Route configuration management backed by DynamoDB.

  Configurations are stored in the config table with:
    pk = "route"
    sk = "\#{route_id}"

  Uses ex_aws_dynamo which auto-encodes plain Elixir values via
  `Dynamo.Encoder.encode_root/1` for put_item, get_item, delete_item keys,
  and expression_attribute_values (with auto-prepended ":" prefix).
  """

  @pk_value "route"

  @doc """
  Save a route configuration to DynamoDB. Creates or updates.
  """
  @spec save(map()) :: {:ok, map()} | {:error, term()}
  def save(route_config) when is_map(route_config) do
    config = normalize_keys(route_config)

    with :ok <- validate_required(config) do
      now = DateTime.utc_now() |> DateTime.to_iso8601()

      config =
        Map.merge(
          %{
            "enabled" => true,
            "final" => true,
            "position" => 0,
            "description" => nil,
            "inserted_at" => now,
            "updated_at" => now
          },
          config
        )
        |> Map.put("updated_at", now)

      item = %{
        "pk" => @pk_value,
        "sk" => config["id"],
        "id" => config["id"],
        "name" => config["name"],
        "filter" => config["filter"] || "",
        "pipeline_id" => config["pipeline_id"],
        "destination_id" => config["destination_id"],
        "final" => config["final"],
        "enabled" => config["enabled"],
        "position" => config["position"],
        "description" => config["description"],
        "inserted_at" => config["inserted_at"],
        "updated_at" => config["updated_at"]
      }

      case ExAws.Dynamo.put_item(table_name(), item) |> ExAws.request() do
        {:ok, _} -> {:ok, config}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc """
  Get a route configuration by ID.
  """
  @spec get(String.t()) :: {:ok, map() | nil}
  def get(route_id) when is_binary(route_id) do
    case ExAws.Dynamo.get_item(table_name(), %{"pk" => @pk_value, "sk" => route_id})
         |> ExAws.request() do
      {:ok, %{"Item" => item}} when map_size(item) > 0 ->
        {:ok, item_to_config(item)}

      {:ok, _} ->
        {:ok, nil}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  List all route configurations, sorted by position ascending.
  """
  @spec list() :: {:ok, [map()]}
  def list do
    query =
      ExAws.Dynamo.query(table_name(),
        key_condition_expression: "pk = :pk",
        expression_attribute_values: %{pk: @pk_value}
      )

    case ExAws.request(query) do
      {:ok, %{"Items" => items}} ->
        configs =
          items
          |> Enum.map(&item_to_config/1)
          |> Enum.sort_by(& &1["position"])

        {:ok, configs}

      {:ok, _} ->
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Delete a route configuration by ID.
  """
  @spec delete(String.t()) :: :ok | {:error, term()}
  def delete(route_id) when is_binary(route_id) do
    case ExAws.Dynamo.delete_item(table_name(), %{"pk" => @pk_value, "sk" => route_id})
         |> ExAws.request() do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # --- Private ---

  defp validate_required(config) do
    missing =
      Enum.filter(~w(id name pipeline_id destination_id), fn field ->
        val = Map.get(config, field)
        is_nil(val) or val == ""
      end)

    case missing do
      [] -> :ok
      fields -> {:error, {:missing_fields, fields}}
    end
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
      "filter" => get_s(item, "filter"),
      "pipeline_id" => get_s(item, "pipeline_id"),
      "destination_id" => get_s(item, "destination_id"),
      "final" => get_bool(item, "final"),
      "enabled" => get_bool(item, "enabled"),
      "position" => get_n(item, "position"),
      "description" => get_s(item, "description"),
      "inserted_at" => get_s(item, "inserted_at"),
      "updated_at" => get_s(item, "updated_at")
    }
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

  defp get_n(item, key) do
    case Map.get(item, key) do
      %{"N" => val} -> String.to_integer(val)
      _ -> 0
    end
  end

  defp table_name do
    prefix = Application.get_env(:compressr, :dynamodb_table_prefix, "compressr_")
    "#{prefix}config"
  end
end
