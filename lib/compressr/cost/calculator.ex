defmodule Compressr.Cost.Calculator do
  @moduledoc """
  Joins usage metrics from `Compressr.Cost.Tracker` with pricing data from
  `Compressr.Cost.Pricing` to produce estimated cost breakdowns.
  """

  alias Compressr.Cost.{Pricing, Tracker}

  @doc """
  Calculates the estimated cost breakdown for a specific resource.

  Returns a map with cost per category and a total.

  ## Example

      %{
        s3_storage: 23.0,
        s3_requests: 5.0,
        glacier_restore: 0.0,
        cross_az: 12.0,
        dynamodb: 0.5,
        total: 40.5
      }
  """
  def calculate_cost(resource_id, opts \\ []) do
    tracker = Keyword.get(opts, :tracker, Tracker)
    pricing = Keyword.get(opts, :pricing, Pricing)

    usage = Tracker.get_usage(resource_id, tracker)
    build_cost_breakdown(usage, pricing)
  end

  @doc """
  Calculates the total estimated cost across all resources.
  """
  def calculate_total(opts \\ []) do
    tracker = Keyword.get(opts, :tracker, Tracker)
    pricing = Keyword.get(opts, :pricing, Pricing)

    all_usage = Tracker.get_all_usage(tracker)

    all_usage
    |> Enum.reduce(empty_breakdown(), fn {_resource_id, usage}, acc ->
      breakdown = build_cost_breakdown(usage, pricing)

      %{
        s3_storage: acc.s3_storage + breakdown.s3_storage,
        s3_requests: acc.s3_requests + breakdown.s3_requests,
        glacier_restore: acc.glacier_restore + breakdown.glacier_restore,
        cross_az: acc.cross_az + breakdown.cross_az,
        dynamodb: acc.dynamodb + breakdown.dynamodb,
        total: acc.total + breakdown.total
      }
    end)
  end

  @doc """
  Returns a cost estimate for a Glacier restore operation.
  """
  def estimate_glacier_restore(bytes, tier, opts \\ []) do
    pricing = Keyword.get(opts, :pricing, Pricing)
    gb = bytes / (1024 * 1024 * 1024)
    rate = Pricing.get_price(:glacier_restore, tier, pricing)

    case rate do
      {:error, _} = err -> err
      rate -> Float.round(gb * rate, 6)
    end
  end

  @doc """
  Projects monthly cost from current usage rate for a specific resource.

  Uses the time elapsed since the tracker's last reset to extrapolate
  a full month cost.
  """
  def estimate_monthly(resource_id, opts \\ []) do
    tracker = Keyword.get(opts, :tracker, Tracker)
    pricing = Keyword.get(opts, :pricing, Pricing)
    now = Keyword.get(opts, :now, DateTime.utc_now())

    usage = Tracker.get_usage(resource_id, tracker)
    breakdown = build_cost_breakdown(usage, pricing)

    # If no usage, return zero breakdown
    if breakdown.total == 0.0 do
      breakdown
    else
      # Calculate elapsed days (minimum 1 to avoid division by zero)
      days_in_month = 30
      elapsed_seconds = max(DateTime.diff(now, Keyword.get(opts, :period_start, now), :second), 1)
      elapsed_days = max(elapsed_seconds / 86_400, 0.001)
      multiplier = days_in_month / elapsed_days

      %{
        s3_storage: Float.round(breakdown.s3_storage * multiplier, 2),
        s3_requests: Float.round(breakdown.s3_requests * multiplier, 2),
        glacier_restore: Float.round(breakdown.glacier_restore * multiplier, 2),
        cross_az: Float.round(breakdown.cross_az * multiplier, 2),
        dynamodb: Float.round(breakdown.dynamodb * multiplier, 2),
        total: Float.round(breakdown.total * multiplier, 2)
      }
    end
  end

  # Private helpers

  defp build_cost_breakdown(usage, pricing) when map_size(usage) == 0 do
    _ = pricing
    empty_breakdown()
  end

  defp build_cost_breakdown(usage, pricing) do
    s3_storage = calculate_s3_storage(usage, pricing)
    s3_requests = calculate_s3_requests(usage, pricing)
    glacier = calculate_glacier_restore(usage, pricing)
    cross_az = calculate_cross_az(usage, pricing)
    dynamodb = calculate_dynamodb(usage, pricing)

    total = Float.round(s3_storage + s3_requests + glacier + cross_az + dynamodb, 6)

    %{
      s3_storage: s3_storage,
      s3_requests: s3_requests,
      glacier_restore: glacier,
      cross_az: cross_az,
      dynamodb: dynamodb,
      total: total
    }
  end

  defp calculate_s3_storage(usage, pricing) do
    bytes = Map.get(usage, :s3_bytes_written, 0)
    gb = bytes / (1024 * 1024 * 1024)
    rate = Pricing.get_price(:s3_storage, :standard, pricing)
    safe_multiply(gb, rate)
  end

  defp calculate_s3_requests(usage, pricing) do
    puts = Map.get(usage, :s3_put_count, 0)
    gets = Map.get(usage, :s3_get_count, 0)

    put_rate = Pricing.get_price(:s3_put, :standard, pricing)
    get_rate = Pricing.get_price(:s3_get, :standard, pricing)

    put_cost = safe_multiply(puts / 1000, put_rate)
    get_cost = safe_multiply(gets / 1000, get_rate)

    Float.round(put_cost + get_cost, 6)
  end

  defp calculate_glacier_restore(usage, pricing) do
    tiers = [:bulk, :standard, :expedited]

    Enum.reduce(tiers, 0.0, fn tier, acc ->
      metric = String.to_existing_atom("glacier_restore_bytes_#{tier}")
      bytes = Map.get(usage, metric, 0)
      gb = bytes / (1024 * 1024 * 1024)
      rate = Pricing.get_price(:glacier_restore, tier, pricing)
      acc + safe_multiply(gb, rate)
    end)
    |> Float.round(6)
  end

  defp calculate_cross_az(usage, pricing) do
    bytes = Map.get(usage, :cross_az_bytes, 0)
    gb = bytes / (1024 * 1024 * 1024)
    rate = Pricing.get_price(:cross_az_transfer, :per_gb, pricing)
    safe_multiply(gb, rate)
  end

  defp calculate_dynamodb(usage, pricing) do
    rcu = Map.get(usage, :dynamo_rcu, 0)
    wcu = Map.get(usage, :dynamo_wcu, 0)

    rcu_rate = Pricing.get_price(:dynamodb, :per_rcu, pricing)
    wcu_rate = Pricing.get_price(:dynamodb, :per_wcu, pricing)

    rcu_cost = safe_multiply(rcu, rcu_rate)
    wcu_cost = safe_multiply(wcu, wcu_rate)

    Float.round(rcu_cost + wcu_cost, 6)
  end

  defp safe_multiply(_value, {:error, _}), do: 0.0
  defp safe_multiply(value, rate) when is_number(value) and is_number(rate), do: value * rate

  defp empty_breakdown do
    %{
      s3_storage: 0.0,
      s3_requests: 0.0,
      glacier_restore: 0.0,
      cross_az: 0.0,
      dynamodb: 0.0,
      total: 0.0
    }
  end
end
