defmodule Compressr.Destination.Config do
  @moduledoc """
  Destination configuration management backed by DynamoDB.

  Configurations are stored in the config table with:
    pk = "destination"
    sk = "\#{destination_id}"

  Uses ex_aws_dynamo which auto-encodes plain Elixir values via
  `Dynamo.Encoder.encode_root/1` for put_item, get_item, delete_item keys,
  and expression_attribute_values (with auto-prepended ":" prefix).
  """

  @pk_value "destination"

  defstruct [
    :id,
    :name,
    :type,
    :config,
    :enabled,
    :post_processing_pipeline_id,
    :backpressure_mode,
    :inserted_at,
    :updated_at
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          type: String.t(),
          config: map(),
          enabled: boolean(),
          post_processing_pipeline_id: String.t() | nil,
          backpressure_mode: :block | :drop | :queue,
          inserted_at: String.t(),
          updated_at: String.t()
        }

  @doc """
  Save a destination configuration to DynamoDB. Creates or updates.
  """
  @spec save(t()) :: {:ok, t()} | {:error, term()}
  def save(%__MODULE__{} = dest_config) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    dest_config =
      dest_config
      |> Map.put(:id, dest_config.id || generate_id())
      |> Map.put(:inserted_at, dest_config.inserted_at || now)
      |> Map.put(:updated_at, now)

    # Plain Elixir values — ex_aws_dynamo auto-encodes them
    item = %{
      "pk" => @pk_value,
      "sk" => dest_config.id,
      "name" => dest_config.name || "",
      "type" => dest_config.type || "",
      "config" => Jason.encode!(dest_config.config || %{}),
      "enabled" => dest_config.enabled == true,
      "backpressure_mode" => to_string(dest_config.backpressure_mode || :block),
      "post_processing_pipeline_id" => dest_config.post_processing_pipeline_id || "",
      "inserted_at" => dest_config.inserted_at,
      "updated_at" => dest_config.updated_at
    }

    case ExAws.Dynamo.put_item(table_name(), item) |> ExAws.request() do
      {:ok, _} -> {:ok, dest_config}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Get a destination configuration by ID.
  """
  @spec get(String.t()) :: {:ok, t()} | {:ok, nil} | {:error, term()}
  def get(id) do
    # Keys are auto-encoded by ex_aws_dynamo
    case ExAws.Dynamo.get_item(table_name(), %{"pk" => @pk_value, "sk" => id})
         |> ExAws.request() do
      {:ok, %{"Item" => item}} when map_size(item) > 0 ->
        {:ok, item_to_struct(item)}

      {:ok, _} ->
        {:ok, nil}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  List all destination configurations.
  """
  @spec list() :: {:ok, [t()]} | {:error, term()}
  def list do
    # expression_attribute_values keys get ":" auto-prepended by ex_aws_dynamo
    query =
      ExAws.Dynamo.query(table_name(),
        key_condition_expression: "pk = :pk",
        expression_attribute_values: %{"pk" => @pk_value}
      )

    case ExAws.request(query) do
      {:ok, %{"Items" => items}} ->
        {:ok, Enum.map(items, &item_to_struct/1)}

      {:ok, _} ->
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Delete a destination configuration by ID.
  """
  @spec delete(String.t()) :: :ok | {:error, term()}
  def delete(id) do
    case ExAws.Dynamo.delete_item(table_name(), %{"pk" => @pk_value, "sk" => id})
         |> ExAws.request() do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # --- Private ---

  defp item_to_struct(item) do
    pp_id = get_s(item, "post_processing_pipeline_id")

    %__MODULE__{
      id: get_s(item, "sk"),
      name: get_s(item, "name"),
      type: get_s(item, "type"),
      config: parse_config(get_s(item, "config")),
      enabled: get_bool(item, "enabled"),
      post_processing_pipeline_id: if(pp_id == "", do: nil, else: pp_id),
      backpressure_mode: parse_backpressure_mode(get_s(item, "backpressure_mode")),
      inserted_at: get_s(item, "inserted_at"),
      updated_at: get_s(item, "updated_at")
    }
  end

  defp parse_config(nil), do: %{}

  defp parse_config(json) do
    case Jason.decode(json) do
      {:ok, map} when is_map(map) -> map
      _ -> %{}
    end
  end

  defp parse_backpressure_mode("block"), do: :block
  defp parse_backpressure_mode("drop"), do: :drop
  defp parse_backpressure_mode("queue"), do: :queue
  defp parse_backpressure_mode(_), do: :block

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

  defp generate_id do
    Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
  end

  defp table_name do
    prefix = Application.get_env(:compressr, :dynamodb_table_prefix, "compressr_")
    "#{prefix}config"
  end
end
