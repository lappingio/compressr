defmodule Compressr.Cost.Pricing do
  @moduledoc """
  AWS pricing tables for cost estimation.

  Prices are configurable via application config under `:compressr, Compressr.Cost.Pricing`.
  Defaults are based on current us-east-1 on-demand prices.
  Runtime updates are supported via `update_price/3`.
  """

  use Agent

  @default_pricing %{
    # S3 storage per GB/month by storage class
    s3_storage: %{
      standard: 0.023,
      intelligent_tiering: 0.023,
      standard_ia: 0.0125,
      one_zone_ia: 0.01,
      glacier_instant: 0.004,
      glacier_flexible: 0.0036,
      glacier_deep_archive: 0.00099
    },
    # S3 API operations per 1,000 requests
    s3_put: %{
      standard: 0.005,
      intelligent_tiering: 0.005,
      standard_ia: 0.01,
      one_zone_ia: 0.01,
      glacier_instant: 0.02,
      glacier_flexible: 0.03,
      glacier_deep_archive: 0.05
    },
    s3_get: %{
      standard: 0.0004,
      intelligent_tiering: 0.0004,
      standard_ia: 0.001,
      one_zone_ia: 0.001,
      glacier_instant: 0.01,
      glacier_flexible: 0.0004,
      glacier_deep_archive: 0.0004
    },
    # Glacier restore per GB by retrieval tier
    glacier_restore: %{
      bulk: 0.0025,
      standard: 0.01,
      expedited: 0.03
    },
    # Cross-AZ data transfer per GB
    cross_az_transfer: %{
      per_gb: 0.01
    },
    # DynamoDB on-demand pricing
    dynamodb: %{
      per_rcu: 0.00000025,
      per_wcu: 0.00000125
    },
    # Athena query pricing per TB scanned
    athena: %{
      per_tb_scanned: 5.0
    }
  }

  @doc """
  Starts the pricing agent, loading initial prices from application config
  or using defaults.
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    configured = Application.get_env(:compressr, __MODULE__, %{})
    initial = Map.merge(@default_pricing, configured)
    Agent.start_link(fn -> initial end, name: name)
  end

  @doc """
  Returns the price for a given service and tier/class.

  ## Examples

      iex> Compressr.Cost.Pricing.get_price(:s3_put, :standard)
      0.005

      iex> Compressr.Cost.Pricing.get_price(:glacier_restore, :bulk)
      0.0025
  """
  def get_price(service, tier, name \\ __MODULE__) do
    Agent.get(name, fn pricing ->
      case Map.get(pricing, service) do
        nil -> {:error, :unknown_service}
        tier_map when is_map(tier_map) -> Map.get(tier_map, tier, {:error, :unknown_tier})
        value -> value
      end
    end)
  end

  @doc """
  Returns the full pricing map for a given service.
  """
  def get_service_pricing(service, name \\ __MODULE__) do
    Agent.get(name, fn pricing ->
      Map.get(pricing, service, {:error, :unknown_service})
    end)
  end

  @doc """
  Returns the entire pricing configuration.
  """
  def get_all(name \\ __MODULE__) do
    Agent.get(name, & &1)
  end

  @doc """
  Updates the price for a given service and tier at runtime.
  """
  def update_price(service, tier, price, name \\ __MODULE__) do
    Agent.update(name, fn pricing ->
      service_map = Map.get(pricing, service, %{})
      updated_service = Map.put(service_map, tier, price)
      Map.put(pricing, service, updated_service)
    end)
  end

  @doc """
  Returns the default pricing map (useful for resetting or reference).
  """
  def default_pricing, do: @default_pricing
end
