defmodule Compressr.Cost.Estimator do
  @moduledoc """
  Pre-action cost estimation for expensive AWS operations.

  Provides cost estimates before initiating Glacier restores or Athena queries,
  enabling operators to make informed decisions.
  """

  alias Compressr.Cost.Pricing

  @glacier_tiers [
    %{
      tier: :bulk,
      time_hours: "5-12",
      description: "Lowest cost, 5-12 hour retrieval"
    },
    %{
      tier: :standard,
      time_hours: "3-5",
      description: "Standard retrieval, 3-5 hours"
    },
    %{
      tier: :expedited,
      time_hours: "1-5 minutes",
      description: "Fastest retrieval, 1-5 minutes"
    }
  ]

  @doc """
  Estimates the cost of a Glacier replay across all retrieval tiers.

  Returns a list of tier comparison maps sorted from cheapest to most expensive.

  ## Parameters

    * `object_count` - Number of objects to restore
    * `total_bytes` - Total bytes across all objects

  ## Example

      iex> Compressr.Cost.Estimator.estimate_glacier_replay(1000, 10_737_418_240)
      [
        %{tier: :bulk, cost: 0.025, time_hours: "5-12", per_gb: 0.0025},
        %{tier: :standard, cost: 0.1, time_hours: "3-5", per_gb: 0.01},
        %{tier: :expedited, cost: 0.3, time_hours: "1-5 minutes", per_gb: 0.03}
      ]
  """
  def estimate_glacier_replay(object_count, total_bytes, opts \\ []) do
    pricing = Keyword.get(opts, :pricing, Pricing)
    _object_count = object_count
    total_gb = total_bytes / (1024 * 1024 * 1024)

    @glacier_tiers
    |> Enum.map(fn tier_info ->
      per_gb = Pricing.get_price(:glacier_restore, tier_info.tier, pricing)

      cost =
        case per_gb do
          {:error, _} -> 0.0
          rate -> Float.round(total_gb * rate, 6)
        end

      %{
        tier: tier_info.tier,
        cost: cost,
        time_hours: tier_info.time_hours,
        per_gb: per_gb
      }
    end)
  end

  @doc """
  Estimates the cost of an Athena query based on estimated bytes scanned.

  Athena charges $5 per TB of data scanned (us-east-1).

  ## Parameters

    * `estimated_bytes_scanned` - Estimated bytes the query will scan

  ## Example

      iex> Compressr.Cost.Estimator.estimate_athena_query(1_099_511_627_776)
      %{bytes_scanned: 1_099_511_627_776, tb_scanned: 1.0, estimated_cost: 5.0}
  """
  def estimate_athena_query(estimated_bytes_scanned, opts \\ []) do
    pricing = Keyword.get(opts, :pricing, Pricing)
    tb = estimated_bytes_scanned / (1024 * 1024 * 1024 * 1024)

    per_tb = Pricing.get_price(:athena, :per_tb_scanned, pricing)

    cost =
      case per_tb do
        {:error, _} -> 0.0
        rate -> Float.round(tb * rate, 6)
      end

    %{
      bytes_scanned: estimated_bytes_scanned,
      tb_scanned: Float.round(tb, 6),
      estimated_cost: cost
    }
  end
end
